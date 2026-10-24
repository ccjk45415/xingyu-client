import 'package:flutter/foundation.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Test bases are isolated from stable patches. No installer or consent dialog.
class PatchUpdates extends ChangeNotifier {
  ShorebirdUpdater? _updater;
  ShorebirdUpdater get updater => _updater ??= ShorebirdUpdater();
  final UpdateTrack track;
  PatchUpdates({ShorebirdUpdater? updater, UpdateTrack? track})
    // Keep the injectable public parameter separate from the lazy private field.
    // ignore: prefer_initializing_formals
    : _updater = updater,
      track =
          track ??
          const UpdateTrack(
            String.fromEnvironment(
              'XINGYU_PATCH_TRACK',
              defaultValue: 'staging',
            ),
          );
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
      current = (await updater.readCurrentPatch())?.number ?? 0;
      final status = await updater.checkForUpdate(track: track);
      if (status == UpdateStatus.outdated) {
        message = '正在后台下载补丁';
        changed();
        await updater.update(track: track);
      }
      next = (await updater.readNextPatch())?.number ?? current;
      message = next != current || status == UpdateStatus.restartRequired
          ? '补丁已就绪，下次完全退出后打开生效'
          : '已是最新补丁';
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
