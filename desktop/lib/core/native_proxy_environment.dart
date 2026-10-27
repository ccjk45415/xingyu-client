import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Process-local environment bridge for the pinned Shorebird updater's ureq.
/// Does not edit OS proxy settings, registry, shell profile or certificate trust.
class NativeProxyEnvironment {
  static final keys = Platform.isWindows
      ? ['ALL_PROXY', 'HTTPS_PROXY', 'HTTP_PROXY', 'NO_PROXY']
      : [
          'ALL_PROXY',
          'all_proxy',
          'HTTPS_PROXY',
          'https_proxy',
          'HTTP_PROXY',
          'http_proxy',
          'NO_PROXY',
          'no_proxy',
        ];
  static final original = {
    for (final key in keys)
      key:
          Platform.environment[key] ??
          (Platform.isWindows
              ? Platform.environment.entries
                    .where((e) => e.key.toUpperCase() == key)
                    .firstOrNull
                    ?.value
              : null),
  };
  static int _leases = 0;
  static Map<String, String?>? _pending;
  static String? _last;
  static bool supported = true;
  static void apply(String? proxy, {bool direct = false}) {
    final values = proxy == null && !direct
        ? Map<String, String?>.of(original)
        : {
            for (final key in keys)
              key: key.toLowerCase() == 'no_proxy'
                  ? (direct ? '*' : 'localhost,127.0.0.1,::1')
                  : (proxy ?? ''),
          };
    final fingerprint = values.toString();
    if (_last == fingerprint) {
      _pending = null;
      return;
    }
    if (_leases > 0) {
      _pending = values;
      return;
    }
    _write(values);
    _last = supported ? fingerprint : null;
  }

  static void _write(Map<String, String?> values) {
    try {
      if (Platform.isWindows) {
        final set = DynamicLibrary.open('kernel32.dll')
            .lookupFunction<
              Int32 Function(Pointer<Utf16>, Pointer<Utf16>),
              int Function(Pointer<Utf16>, Pointer<Utf16>)
            >('SetEnvironmentVariableW');
        for (final e in values.entries) {
          final key = e.key.toNativeUtf16(), value = e.value?.toNativeUtf16();
          try {
            if (set(key, value ?? nullptr) == 0) {
              throw const OSError('proxy environment');
            }
          } finally {
            calloc.free(key);
            if (value != null) calloc.free(value);
          }
        }
      } else if (Platform.isAndroid || Platform.isMacOS || Platform.isLinux) {
        final library = Platform.isAndroid
            ? DynamicLibrary.open('libc.so')
            : DynamicLibrary.process();
        final set = library
            .lookupFunction<
              Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
              int Function(Pointer<Utf8>, Pointer<Utf8>, int)
            >('setenv');
        final unset = library
            .lookupFunction<
              Int32 Function(Pointer<Utf8>),
              int Function(Pointer<Utf8>)
            >('unsetenv');
        for (final e in values.entries) {
          final key = e.key.toNativeUtf8(), value = e.value?.toNativeUtf8();
          try {
            if ((value == null ? unset(key) : set(key, value, 1)) != 0) {
              throw const OSError('proxy environment');
            }
          } finally {
            calloc.free(key);
            if (value != null) calloc.free(value);
          }
        }
      }
      supported = true;
    } catch (_) {
      supported = false;
    }
  }

  static Future<T> lease<T>(Future<T> Function() action) async {
    _leases++;
    try {
      return await action();
    } finally {
      _leases--;
      if (_leases == 0 && _pending != null) {
        final next = _pending!;
        _pending = null;
        _write(next);
        _last = supported ? next.toString() : null;
      }
    }
  }
}
