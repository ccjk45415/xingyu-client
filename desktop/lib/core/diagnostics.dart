import 'dart:convert';
import 'dart:io';

import 'native_storage.dart';
import 'system_notices.dart';
import 'patch_updates.dart';

import 'package:path_provider/path_provider.dart';

import 'api.dart';

import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Explicit command-line diagnostics; touches only a random temporary key/file and public health.
Future<void> runSelfCheck({
  bool offline = false,
  bool downloadPatch = false,
}) async {
  if (downloadPatch) {
    final patches = PatchUpdates();
    await patches.check(force: true);
    if (patches.message.contains('重试') || patches.message.contains('未就绪')) {
      throw StateError('Patch check failed');
    }
    patches.dispose();
  }
  final symbols = ShorebirdUpdater().isAvailable;
  final native = await SystemNotices().status();
  final codePush =
      symbols && (!Platform.isWindows || native['patchReady'] == true);
  if (const bool.fromEnvironment('XINGYU_REQUIRE_CODE_PUSH') && !codePush) {
    throw StateError('Required patch engine is unavailable');
  }
  final key = 'xingyu.selfcheck.${nonce()}', value = '星屿 · ${nonce()} ✦';
  const storage = SecureVault();
  File? file;
  final service = ServiceApi();
  try {
    await storage.write(key: key, value: value);
    if (await storage.read(key: key) != value) {
      throw StateError('Secure storage round trip failed');
    }
    if (Platform.isWindows) {
      final protected = File(
        '${Platform.environment['LOCALAPPDATA']}/XingyuDesktop/Secure/$key.bin',
      );
      final cipher = await protected.readAsBytes();
      if (utf8.decode(cipher, allowMalformed: true).contains(value)) {
        throw StateError('Session was written without encryption');
      }
      cipher[cipher.length - 1] ^= 1;
      await protected.writeAsBytes(cipher, flush: true);
      bool rejected = false;
      try {
        await storage.read(key: key);
      } catch (_) {
        rejected = true;
      }
      if (!rejected) {
        throw StateError('Encrypted session integrity check failed');
      }
    }
    await storage.delete(key: key);
    final support = await getApplicationSupportDirectory();
    file = File('${support.path}/selfcheck-${nonce()}.tmp');
    await file.parent.create(recursive: true);
    await file.writeAsString('xingyu-diagnostic');
    if (await file.readAsString() != 'xingyu-diagnostic') {
      throw StateError('Application directory unavailable');
    }
    await file.delete();
    file = null;
    if (!offline) {
      final health = await service.request('/health');
      if (health['protocol'] != 3 || health['channel_count'] != 2) {
        throw StateError('Unexpected service protocol');
      }
    }
    stdout.writeln(
      jsonEncode({
        if (Platform.isWindows) 'windows_native_engine': 'pass',
        'code_push_engine': codePush ? 'available' : 'unavailable',
        'code_push_initialized': codePush,
        'patch_probe': const int.fromEnvironment(
          'XINGYU_PATCH_PROBE',
          defaultValue: 0,
        ),
        'current_patch': symbols
            ? (await ShorebirdUpdater().readCurrentPatch())?.number ?? 0
            : 0,
        'next_patch': symbols
            ? (await ShorebirdUpdater().readNextPatch())?.number ?? 0
            : 0,
        'system_notifications_native': native['supported'] == true,
        if (Platform.isMacOS) 'macos_native_engine': 'pass',
        if (Platform.isMacOS) 'keychain_round_trip': 'pass',
        'secure_storage': 'pass',
        if (Platform.isWindows) 'encrypted_file_and_tamper_rejection': 'pass',
        'app_data_directory': 'pass',
        'public_health': offline ? 'skipped_offline' : 'pass',
        'protocol': 3,
        'website_password_used': false,
        'messages_sent': 0,
      }),
    );
    await stdout.flush();
    exit(0);
  } catch (e) {
    stderr.writeln('Xingyu native self-check failed: $e');
    exitCode = 1;
  } finally {
    service.close();
    try {
      await storage.delete(key: key);
      if (file != null && await file.exists()) await file.delete();
    } catch (_) {}
  }
  exit(exitCode);
}
