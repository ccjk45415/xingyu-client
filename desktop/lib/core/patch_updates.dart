import 'dart:io';

import 'package:flutter/foundation.dart';

import 'system_notices.dart';
import 'native_proxy_environment.dart';
import 'platform.dart';

import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Silent Dart patches are tied to the exact native base and update track.
class PatchUpdates extends ChangeNotifier {
  ShorebirdUpdater? _updater;
  ShorebirdUpdater get updater => _updater ??= ShorebirdUpdater();
  final UpdateTrack track;
  PatchUpdates({ShorebirdUpdater? updater, UpdateTrack? track})
    // Keep the injectable public parameter separate from the lazy private field.
    // ignore: prefer_initializing_formals
    : _updater = updater,
      _provided = updater != null,
      track =
          track ??
          const UpdateTrack(
            String.fromEnvironment(
              'XINGYU_PATCH_TRACK',
              defaultValue: 'staging',
            ),
          );
  bool get _injected => _provided;
  final bool _provided;
  bool busy = false, _disposed = false;
  int current = 0, next = 0;
  String message = '等待检查';
  DateTime _checked = DateTime(2000);
  bool get available => updater.isAvailable;
  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> check({bool force = false}) async {
    if (_disposed ||
        busy ||
        !force &&
            DateTime.now().difference(_checked) < const Duration(minutes: 30)) {
      return;
    }
    if (!available) {
      message = '当前构建未启用补丁引擎';
      changed();
      return;
    }
    busy = true;
    _checked = DateTime.now();
    message = '后台检查中';
    changed();
    try {
      if (Platform.isWindows &&
          !_injected &&
          (await SystemNotices().status())['patchReady'] != true) {
        message = '补丁引擎尚未就绪，请安装最新完整版本';
        return;
      }
      if (!_injected) {
        try {
          await refreshSystemProxy();
        } catch (_) {}
      }
      await NativeProxyEnvironment.lease(() async {
        current = (await updater.readCurrentPatch())?.number ?? 0;
        final status = await updater.checkForUpdate(track: track);
        if (status == UpdateStatus.outdated ||
            status == UpdateStatus.upToDate) {
          // The SDK's boolean check also returns false on native/network errors.
          // The result-bearing update call distinguishes "no update" from failure.
          message = status == UpdateStatus.outdated ? '正在后台下载补丁' : '正在确认补丁状态';
          changed();
          await updater.update(track: track);
        }
        next = (await updater.readNextPatch())?.number ?? current;
        message = next != current || status == UpdateStatus.restartRequired
            ? '补丁已就绪，下次完全退出后打开生效'
            : '已是最新补丁';
      });
    } catch (_) {
      message = '暂时无法检查补丁，将在下次联网时重试';
    } finally {
      busy = false;
      changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
