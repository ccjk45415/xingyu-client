import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/platform.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/pages/account.dart';
import 'package:xingyu_desktop/ui/shared.dart';

class NoUpdateService extends ServiceApi {
  int requests = 0;
  @override
  Future<Json> request(
    String path, {
    String? token,
    Json? body,
    String? method,
  }) async {
    requests++;
    expect(path, '/updates/macos.json');
    return {'available': false};
  }
}

void main() {
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    SecureVault.setMockInitialValues({});
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('macOS has independent version, system fonts and Command shortcuts', () {
    expect(clientVersion, '0.3.0');
    expect(clientBuild, 4);
    expect(uiFont, null);
    expect(monoFont, 'Menlo');
    expect(secureStorageLabel, 'macOS 钥匙串');
    expect(primaryShortcut(LogicalKeyboardKey.keyS).meta, true);
    expect(primaryShortcut(LogicalKeyboardKey.keyS).control, false);
    expect(primaryShortcut(LogicalKeyboardKey.keyZ, shift: true).shift, true);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(primaryShortcut(LogicalKeyboardKey.keyS).control, true);
    expect(clientVersion, desktopVersion);
    expect(clientBuild, desktopBuild);
    expect(backShortcutLabel, 'Alt+←');
  });

  test(
    'native proxy settings are validated, including IPv6 and invalid ports',
    () {
      expect(proxyDirective('127.0.0.1', 7890), 'PROXY 127.0.0.1:7890');
      expect(proxyDirective('::1', 7890), 'PROXY [::1]:7890');
      expect(proxyDirective('proxy.example', 8080), 'PROXY proxy.example:8080');
      for (final port in [0, -1, 65536, 1.5, double.nan, null, '8080']) {
        expect(proxyDirective('localhost', port), 'DIRECT');
      }
      for (final host in [
        '',
        'host; DIRECT',
        'user@host',
        'http://host',
        null,
      ]) {
        expect(proxyDirective(host, 7890), 'DIRECT');
      }
    },
  );

  testWidgets('Command shortcut works without Control on macOS', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CallbackShortcuts(
          bindings: {primaryShortcut(LogicalKeyboardKey.keyK): () => calls++},
          child: const Focus(autofocus: true, child: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('macOS update UI uses its own official update manifest', (
    tester,
  ) async {
    final service = NoUpdateService();
    final state = AppState(serviceApi: service)..user = {'id': 1};
    await tester.pumpWidget(
      MaterialApp(
        home: DeskScope(
          app: state,
          open: (_) {},
          child: const Scaffold(body: SettingsPage('updates')),
        ),
      ),
    );
    expect(find.text('仓库 · 星屿 macOS 客户端'), findsOneWidget);
    expect(find.text('星屿 0.3.0'), findsOneWidget);
    await tester.ensureVisible(find.text('检查新版本'));
    await tester.tap(find.text('检查新版本'));
    await tester.pump();
    await tester.pump();
    expect(find.text('当前没有可用的新版本'), findsOneWidget);
    expect(service.requests, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
