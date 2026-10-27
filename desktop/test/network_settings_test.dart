import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/proxy_config.dart';
import 'package:xingyu_desktop/core/native_proxy_environment.dart';
import 'package:xingyu_desktop/core/platform.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/pages/network_settings.dart';
import 'package:xingyu_desktop/ui/shared.dart';

String? nativeEnvironment(String key) {
  if (Platform.isWindows) {
    final get = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<
          Uint32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
          int Function(Pointer<Utf16>, Pointer<Utf16>, int)
        >('GetEnvironmentVariableW');
    final name = key.toNativeUtf16(), out = calloc<Uint16>(4096);
    try {
      final n = get(name, out.cast(), 4096);
      return n == 0 ? null : out.cast<Utf16>().toDartString(length: n);
    } finally {
      calloc.free(name);
      calloc.free(out);
    }
  }
  final get = DynamicLibrary.process()
      .lookupFunction<
        Pointer<Utf8> Function(Pointer<Utf8>),
        Pointer<Utf8> Function(Pointer<Utf8>)
      >('getenv');
  final name = key.toNativeUtf8();
  try {
    final result = get(name);
    return result == nullptr ? null : result.toDartString();
  } finally {
    calloc.free(name);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => configureNetworkProxy(null));
  test('manual HTTP and mixed ports support LAN and IPv6; reject credentials and invalid addresses', () {
    for (final host in [
      '192.168.1.100',
      '127.0.0.1',
      'clash.lan',
      '::1',
      '[::1]',
    ]) {
      expect(
        NetworkProxyConfig.parse({'mode': 'manual', 'host': host, 'port': 7890})
            .mode,
        'manual',
      );
    }
    for (final host in [
      'http://192.168.1.100',
      'user:secret@host',
      'foo[bar]',
      '192.168.1.1/abc',
      'x\ny',
    ]) {
      expect(
        () => NetworkProxyConfig.parse({
          'mode': 'manual',
          'host': host,
          'port': 7890,
        }),
        throwsFormatException,
      );
    }
    for (final port in [0, 65536, '7890.5']) {
      expect(
        () => NetworkProxyConfig.parse({
          'mode': 'manual',
          'host': 'localhost',
          'port': port,
        }),
        throwsFormatException,
      );
    }
  });
  test('update-only proxy leaves website routing to system and covers patch check, CDN and installer', () {
    final config = NetworkProxyConfig.parse({
      'mode': 'manual',
      'scope': 'updates',
      'host': '192.168.1.2',
      'port': 7890,
    });
    expect(
      config.directive(
        Uri.parse('https://cangku.moe/api/v1/auth/me'),
        (_) => 'DIRECT',
      ),
      'DIRECT',
    );
    for (final url in [
      'https://api.shorebird.dev/api/v1/patches/check',
      'https://cdn.shorebird.cloud/a.patch',
      'https://xingyu-chat-ccjk45415.pages.dev/releases/app.apk',
      'https://xingyu-chat-ccjk45415.pages.dev/updates/android.json',
    ]) {
      expect(
        config.directive(Uri.parse(url), (_) => 'DIRECT'),
        'PROXY 192.168.1.2:7890',
      );
    }
    expect(
      config.directive(
        Uri.parse('https://cangku.moe/'),
        (_) => 'PROXY system:8080',
      ),
      'PROXY system:8080',
    );
    expect(
      const NetworkProxyConfig(
        mode: 'direct',
      ).directive(Uri.parse('https://cangku.moe'), (_) => 'PROXY system:8080'),
      'DIRECT',
    );
  });
  test('native updater environment is process-local, restores originals and defers changes while a check runs', () async {
    final before = nativeEnvironment('HTTPS_PROXY');
    NativeProxyEnvironment.apply('http://127.0.0.1:17890');
    expect(NativeProxyEnvironment.supported, true);
    expect(nativeEnvironment('HTTPS_PROXY'), 'http://127.0.0.1:17890');
    final gate = Completer<void>();
    final pending = NativeProxyEnvironment.lease(() => gate.future);
    NativeProxyEnvironment.apply('http://127.0.0.1:17891');
    expect(nativeEnvironment('HTTPS_PROXY'), 'http://127.0.0.1:17890');
    NativeProxyEnvironment.apply('http://127.0.0.1:17890');
    gate.complete();
    await pending;
    expect(nativeEnvironment('HTTPS_PROXY'), 'http://127.0.0.1:17890');
    NativeProxyEnvironment.apply(null);
    expect(nativeEnvironment('HTTPS_PROXY'), before);
  });
  testWidgets(
    'network form fits mobile and desktop and restores saved manual settings',
    (tester) async {
      final app = AppState();
      configureNetworkProxy({
        'mode': 'manual',
        'host': '192.168.1.2',
        'port': 7890,
      });
      for (final width in [390.0, 1100.0]) {
        await tester.binding.setSurfaceSize(Size(width, 1200));
        await tester.pumpWidget(
          MaterialApp(
            home: DeskScope(
              app: app,
              open: (_) {},
              child: const Scaffold(body: NetworkSettingsPage()),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('网络与代理'), findsOneWidget);
        expect(find.text('192.168.1.2'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
      await tester.binding.setSurfaceSize(null);
    },
  );
}
