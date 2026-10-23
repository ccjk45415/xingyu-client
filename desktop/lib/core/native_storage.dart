import 'package:flutter/services.dart';

/// Windows DPAPI / Android Keystore / macOS Keychain, implemented by each runner.
class SecureVault {
  static const _channel = MethodChannel('moe.cangku.xingyu/secure_storage');
  static Map<String, String>? _testValues;
  const SecureVault();
  static void setMockInitialValues(Map<String, String> values) {
    _testValues = {...values};
  }

  Future<String?> read({required String key}) async => _testValues != null
      ? _testValues![key]
      : _channel.invokeMethod<String>('read', {'key': key});
  Future<void> write({required String key, required String value}) async {
    if (_testValues != null) {
      _testValues![key] = value;
      return;
    }
    await _channel.invokeMethod<void>('write', {'key': key, 'value': value});
  }

  Future<void> delete({required String key}) async {
    if (_testValues != null) {
      _testValues!.remove(key);
      return;
    }
    await _channel.invokeMethod<void>('delete', {'key': key});
  }
}
