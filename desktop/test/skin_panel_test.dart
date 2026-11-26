import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xingyu_desktop/app.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/skin.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/ui/glass.dart';

class _OfflineSocket extends SocketConnector {
  @override
  Future<WebSocket> connect(
    String url, {
    Map<String, dynamic>? headers,
  }) async => throw const SocketException('Offline UI test');
}

class _FakeSiteApi extends SiteApi {
  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) async => {
    'code': 0,
    'data': const <dynamic>[],
    'meta': {
      'pagination': {'total_pages': 1, 'current_page': 1},
    },
  };
}

class _FakeServiceApi extends ServiceApi {
  @override
  Future<Json> request(
    String path, {
    String? token,
    Json? body,
    String? method,
  }) async => {'ok': true, 'items': const <dynamic>[]};
}

AppState _loggedInApp({Directory? dir}) {
  final app = AppState(
    siteApi: _FakeSiteApi(),
    serviceApi: _FakeServiceApi(),
    socketFactory: _OfflineSocket.new,
  );
  app.directory = dir;
  app.starting = false;
  app.user = {'id': 1001, 'nickname': '测试用户', 'level': 3};
  return app;
}

void main() {
  test('skin and dark mode persist to library.json', () async {
    final dir = await Directory.systemTemp.createTemp('xingyu-skin-persist-');
    addTearDown(() => dir.delete(recursive: true));

    final app = _loggedInApp(dir: dir);
    addTearDown(app.dispose);

    expect(app.skin, AppSkin.classic);
    await app.setDark(true);
    await app.setSkin(AppSkin.glass);

    final saved =
        jsonDecode(await File('${dir.path}/library.json').readAsString())
            as Map<String, dynamic>;
    expect(saved['dark'], isTrue);
    expect(saved['skin'], 'glass');
    expect(AppSkin.parse(saved['skin']), AppSkin.glass);
    await app.setSkin(AppSkin.liquid);
    final savedLiquid =
        jsonDecode(await File('${dir.path}/library.json').readAsString())
            as Map<String, dynamic>;
    expect(savedLiquid['skin'], 'liquid');
    expect(AppSkin.parse(savedLiquid['skin']), AppSkin.liquid);
    expect(AppSkin.parse('unknown'), AppSkin.classic);
  });

  testWidgets(
    'desktop top bar replaces moon button with skin button and switches dark + glass skin',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 820);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final app = _loggedInApp();

      await tester.pumpWidget(XingyuApp(app: app));
      await tester.pump(const Duration(milliseconds: 300));

      // Top bar has skin palette button instead of old moon icon.
      final skinButton = find.byKey(const Key('shell.skinButton'));
      expect(skinButton, findsOneWidget);
      expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
      expect(find.byTooltip('切换深色'), findsNothing);

      // Tap skin button to open the skin & appearance panel.
      await tester.tap(skinButton);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('皮肤与外观'), findsOneWidget);
      expect(find.text('星屿经典'), findsOneWidget);
      expect(find.text('琉璃毛玻璃'), findsOneWidget);
      expect(find.text('液态玻璃'), findsOneWidget);

      // Toggle dark mode inside the panel.
      await tester.tap(find.byKey(const Key('skin.mode.dark')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(app.dark, isTrue);

      // Switch to the Frost Glass skin.
      await tester.tap(find.byKey(const Key('skin.option.glass')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(app.skin, AppSkin.glass);
      expect(find.byType(GlassPanel), findsWidgets);

      // Switch to the Liquid Glass skin.
      await tester.tap(find.byKey(const Key('skin.option.liquid')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(app.skin, AppSkin.liquid);
      expect(find.byType(GlassPanel), findsWidgets);

      // Switch back to classic light mode.
      await tester.tap(find.byKey(const Key('skin.mode.light')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('skin.option.classic')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(app.dark, isFalse);
      expect(app.skin, AppSkin.classic);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'mobile layout exposes skin button and renders floating glass chrome',
    (tester) async {
      tester.view.physicalSize = const Size(420, 860);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final app = _loggedInApp();

      await tester.pumpWidget(XingyuApp(app: app));
      await tester.pump(const Duration(milliseconds: 300));

      final skinButton = find.byKey(const Key('shell.skinButton'));
      expect(skinButton, findsOneWidget);

      await tester.tap(skinButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('皮肤与外观'), findsOneWidget);

      await tester.tap(find.byKey(const Key('skin.option.glass')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(app.skin, AppSkin.glass);
      expect(find.byType(GlassPanel), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
