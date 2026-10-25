import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/core/windows_tray.dart';
import 'package:xingyu_desktop/ui/windows_close.dart';

class FakeTray implements TrayPort {
  int prepared = 0, hidden = 0, shown = 0, closed = 0;
  bool fail = false;
  void Function(String)? command;
  @override
  Future<void> prepare(void Function(String) onCommand) async {
    prepared++;
    command = onCommand;
    if (fail) throw StateError('synthetic');
  }

  @override
  void hide() => hidden++;
  @override
  void show() => shown++;
  @override
  Future<void> dispose() async {
    closed++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SecureVault.setMockInitialValues({}));
  Future<void> mount(WidgetTester tester, AppState app, FakeTray tray) async {
    await tester.binding.setSurfaceSize(const Size(1100, 800));
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      WindowsCloseHost(
        app: app,
        navigatorKey: key,
        trayFactory: () => tray,
        enabled: true,
        child: MaterialApp(
          navigatorKey: key,
          home: const Scaffold(body: Text('main')),
        ),
      ),
    );
  }

  testWidgets(
    'X offers tray/exit, cancellation preserves window; tray remembers preference',
    (tester) async {
      final app = AppState(), tray = FakeTray();
      await mount(tester, app, tray);
      var close = WidgetsBinding.instance.handleRequestAppExit();
      await tester.pumpAndSettle();
      expect(find.text('如何关闭星屿？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await close, AppExitResponse.cancel);
      expect(tray.hidden, 0);
      close = WidgetsBinding.instance.handleRequestAppExit();
      await tester.pumpAndSettle();
      await tester.tap(find.text('记住这次选择'));
      await tester.pump();
      await tester.tap(find.text('最小化到系统托盘'));
      await tester.pumpAndSettle();
      expect(await close, AppExitResponse.cancel);
      expect(tray.hidden, 1);
      expect(app.windowsCloseAction, 'tray');
      close = WidgetsBinding.instance.handleRequestAppExit();
      await tester.pumpAndSettle();
      expect(await close, AppExitResponse.cancel);
      expect(tray.hidden, 2);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
  testWidgets(
    'exit returns engine exit, failed tray leaves window visible and does not remember it',
    (tester) async {
      final app = AppState(), tray = FakeTray()..fail = true;
      await mount(tester, app, tray);
      var close = WidgetsBinding.instance.handleRequestAppExit();
      await tester.pumpAndSettle();
      await tester.tap(find.text('记住这次选择'));
      await tester.tap(find.text('最小化到系统托盘'));
      await tester.pumpAndSettle();
      expect(find.text('暂时无法启动系统托盘'), findsOneWidget);
      expect(tray.hidden, 0);
      expect(app.windowsCloseAction, 'ask');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(await close, AppExitResponse.cancel);
      close = WidgetsBinding.instance.handleRequestAppExit();
      await tester.pumpAndSettle();
      await tester.tap(find.text('退出程序'));
      await tester.pumpAndSettle();
      expect(await close, AppExitResponse.exit);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
