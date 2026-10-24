import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'error_diagnostics.dart';

export 'window_placement.dart';

import 'window_placement.dart';

class WindowMemory with WidgetsBindingObserver {
  final WindowPlacementPort port;
  final File file;
  Timer? _timer;
  String? _saved;
  bool _reported = false;
  WindowMemory({required this.port, required this.file});

  void restore() {
    try {
      if (!file.existsSync() || file.lengthSync() > 4096) return;
      final value = RememberedWindow.decode(
        jsonDecode(file.readAsStringSync()),
      );
      if (value != null) port.restore(value);
    } catch (error, stack) {
      _report(error, stack);
    }
  }

  void capture() {
    try {
      final value = port.read();
      if (value == null) return;
      final encoded = jsonEncode(value.toJson());
      if (encoded == _saved) return;
      file.parent.createSync(recursive: true);
      // Tiny, synchronous replacement: close must not interrupt a pending write.
      final pending = File('${file.path}.tmp');
      pending.writeAsStringSync(encoded, flush: true);
      pending.renameSync(file.path);
      _saved = encoded;
    } catch (error, stack) {
      _report(error, stack);
    }
  }

  void _report(Object error, StackTrace stack) {
    if (_reported) return;
    _reported = true;
    unawaited(appDiagnostics.record(error, stack, 'window-memory'));
  }

  void start() {
    restore();
    capture();
    WidgetsBinding.instance.addObserver(this);
    // Moving the frame does not always generate a Flutter metrics notification.
    _timer = Timer.periodic(
      const Duration(milliseconds: 400),
      (_) => capture(),
    );
  }

  @override
  void didChangeMetrics() => capture();

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    capture();
    return AppExitResponse.exit;
  }

  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}

Future<void> startWindowMemory() async {
  if (!Platform.isWindows) return;
  try {
    final directory = await getApplicationSupportDirectory();
    final port = WindowsPlacement();
    // The runner calls Show(SW_SHOWNORMAL) after its first frame. Wait until that
    // has happened, so it cannot undo restoring a maximized window.
    for (var attempt = 0; attempt < 60; attempt++) {
      if (port.read() != null) {
        WindowMemory(
          port: port,
          file: File('${directory.path}/window-placement-v1.json'),
        ).start();
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  } catch (error, stack) {
    unawaited(appDiagnostics.record(error, stack, 'window-memory-init'));
  }
}
