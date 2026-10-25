import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/state.dart';
import 'core/diagnostics.dart';
import 'core/video_diagnostics.dart';
import 'core/image_diagnostics.dart';
import 'core/media.dart';
import 'core/error_diagnostics.dart';
import 'core/platform.dart';
import 'core/window_memory.dart';

import 'dart:ui';

import 'pages/private.dart';

void main(List<String> args) {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      if (args.length == 2 && args.first == '--video-stream-self-check') {
        unawaited(runVideoPreviewCheck(args[1], publicStream: true));
        return;
      }
      if (args.length == 2 && args.first == '--video-preview-self-check') {
        unawaited(runVideoPreviewCheck(args[1]));
        return;
      }
      if (args.length == 2 && args.first == '--image-self-check') {
        unawaited(runImageSelfCheck(args[1]));
        return;
      }
      if (args.length == 2 && args.first == '--video-self-check') {
        unawaited(runVideoSelfCheck(args[1]));
        return;
      }
      if (args.contains('--self-check')) {
        unawaited(
          runSelfCheck(
            offline: args.contains('--offline'),
            downloadPatch: args.contains('--download-patch'),
          ),
        );
        return;
      }
      FlutterError.onError = (details) {
        unawaited(
          appDiagnostics.record(
            details.exception,
            details.stack ?? StackTrace.current,
            'flutter',
          ),
        );
        FlutterError.presentError(details);
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        unawaited(appDiagnostics.record(error, stack, 'platform'));
        return true;
      };
      try {
        await initializePlatform();
      } catch (e, stack) {
        unawaited(appDiagnostics.record(e, stack, 'platform-init'));
      }
      unawaited(appDiagnostics.initialize());
      final app = AppState();
      app.onLogout = () {
        MediaCache.clear();
        clearPrivateDrafts();
      };
      runApp(XingyuApp(app: app));
      unawaited(startWindowMemory());
      unawaited(app.initialize());
    },
    (error, stack) {
      unawaited(appDiagnostics.record(error, stack, 'zone'));
    },
  );
}
