import 'dart:convert';
import 'dart:io';
import 'native_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'api.dart';

/// Explicit command-line diagnostics; touches only a random temporary key/file and public health.
Future<void> runSelfCheck() async {
  final key = 'xingyu.selfcheck.${nonce()}', value = '星屿 · ${nonce()} ✦';
  const storage = SecureVault();
  File? file;
  final service = ServiceApi();
  try {
    await storage.write(key: key, value: value);
    if (await storage.read(key: key) != value) {
      throw StateError('Secure storage round trip failed');
    }
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
    if (!rejected) throw StateError('Encrypted session integrity check failed');
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
    final health = await service.request('/health');
    if (health['protocol'] != 3 || health['channel_count'] != 2) {
      throw StateError('Unexpected service protocol');
    }
    stdout.writeln(
      jsonEncode({
        'windows_native_engine': 'pass',
        'secure_storage': 'pass',
        'encrypted_file_and_tamper_rejection': 'pass',
        'app_data_directory': 'pass',
        'public_health': 'pass',
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
