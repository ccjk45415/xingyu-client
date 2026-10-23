import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/app.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/pages/authoring.dart';
import 'package:xingyu_desktop/pages/ai_assistant.dart';
import 'package:xingyu_desktop/ui/shared.dart';

import 'widget_test.dart'
    show FakeSite, FakeService, OfflineSocket, frames, capture;

void main() {
  setUpAll(() async {
    for (final (family, path) in [
      ('Microsoft YaHei UI', 'C:/Windows/Fonts/msyh.ttc'),
      (
        'MaterialIcons',
        'C:/codex-tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ),
    ]) {
      final loader = FontLoader(
        family,
      )..addFont(File(path).readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
    }
  });
  setUp(() {
    SecureVault.setMockInitialValues({});
  });

  for (final width in [360.0, 412.0]) {
    testWidgets(
      'phone navigation, editor, long body and AI assistant at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 860);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app =
            AppState(
                siteApi: FakeSite(),
                serviceApi: FakeService(),
                socketFactory: OfflineSocket.new,
              )
              ..starting = false
              ..user = FakeSite.user
              ..categories = [
                {'id': 12, 'name': '测试分类'},
              ]
              ..identity = {
                'token': 'synthetic-mobile-token',
                'expires_at': '2030-01-01T00:00:00Z',
              };
        final shot = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: shot,
            child: XingyuApp(app: app),
          ),
        );
        await frames(tester);
        expect(find.byKey(const ValueKey('mobile.nav.home')), findsOneWidget);
        await capture(tester, shot, 'flutter-android-home-${width.toInt()}');
        for (final kind in [
          'categories',
          'rank',
          'chat',
          'followingFeed',
          'mine',
        ]) {
          await tester.tap(find.byKey(ValueKey('mobile.nav.$kind')));
          await frames(tester);
          expect(tester.takeException(), isNull, reason: kind);
          if (kind == 'chat') {
            expect(find.text('频道一'), findsWidgets);
            await tester.tap(find.text('频道二'));
            await frames(tester);
            expect(tester.takeException(), isNull);
            await capture(
              tester,
              shot,
              'flutter-android-chat-${width.toInt()}',
            );
          }
        }
        await capture(tester, shot, 'flutter-android-account-${width.toInt()}');
        for (final kind in [
          'article',
          'author',
          'manage',
          'drafts',
          'settings',
          'appearance',
          'profile',
          'security',
          'updates',
          'notifications',
          'myComments',
          'history',
          'inbox',
          'dmPeople',
          'dmBlocks',
          'dm',
        ]) {
          tester
              .widget<DeskScope>(find.byType(DeskScope).first)
              .open(DeskRoute(kind, kind, id: kind == 'article' ? 1 : 77));
          await frames(tester);
          expect(tester.takeException(), isNull, reason: '$width / $kind');
        }
        final scope = tester.widget<DeskScope>(find.byType(DeskScope).first);
        scope.open(const DeskRoute('editor', '新建投稿'));
        await frames(tester);
        expect(find.byType(PostEditor), findsOneWidget);
        expect(find.byKey(const ValueKey('mobile.nav.home')), findsNothing);
        await tester.ensureVisible(find.text('AI 投稿助手').first);
        await frames(tester);
        await capture(tester, shot, 'flutter-android-editor-${width.toInt()}');
        await tester.tap(find.text('AI 投稿助手').first);
        await frames(tester);
        expect(find.byType(AiAssistantDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(tester, shot, 'flutter-android-ai-${width.toInt()}');
        await tester.tap(find.byTooltip('关闭助手'));
        await frames(tester);
        await tester.ensureVisible(find.byKey(const Key('editor.content')));
        await tester.enterText(
          find.byKey(const Key('editor.content')),
          List.generate(100, (i) => '长正文第$i行，可使用触摸滑动。').join('\n'),
        );
        await tester.pump(const Duration(seconds: 1));
        await tester.ensureVisible(find.byKey(const Key('editor.content')));
        await frames(tester);
        final field = find.byKey(const Key('editor.content'));
        final scroll = tester.state<ScrollableState>(
          find.descendant(of: field, matching: find.byType(Scrollable)).first,
        );
        expect(scroll.position.maxScrollExtent, greaterThan(0));
        scroll.position.jumpTo(0);
        await tester.pump();
        final visible = tester
            .getRect(field)
            .intersect(Rect.fromLTWH(0, 70, width, 750));
        await tester.dragFrom(visible.center, const Offset(0, -280));
        await frames(tester);
        expect(scroll.position.pixels, greaterThan(0));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        app.dispose();
      },
    );
  }
}
