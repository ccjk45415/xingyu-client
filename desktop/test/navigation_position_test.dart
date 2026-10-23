import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/app.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/browse_cache.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/pages/conversation.dart';
import 'package:xingyu_desktop/pages/discovery.dart';
import 'package:xingyu_desktop/pages/reading.dart';
import 'package:xingyu_desktop/ui/shared.dart';

import 'widget_test.dart' show FakeSite, FakeService, OfflineSocket, frames;

class PositionSite extends FakeSite {
  Completer<Json>? paused;
  Json? pendingResult;
  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) async {
    if ([
      'post/list',
      'post/rank',
      'post/search',
      'user/post',
      'user/favoritePost',
    ].contains(path)) {
      final result = <String, dynamic>{
        'data': [
          for (var i = 1; i <= 30; i++)
            {...FakeSite.posts.first, 'id': i, 'title': '位置测试作品$i'},
        ],
        'meta': {
          'pagination': {'total_pages': 3},
        },
      };
      pendingResult = result;
      return paused?.future ?? result;
    }
    return super.get(path, params);
  }
}

AppState makeApp(PositionSite site) =>
    AppState(
        siteApi: site,
        serviceApi: FakeService(),
        socketFactory: OfflineSocket.new,
      )
      ..starting = false
      ..user = {...FakeSite.user}
      ..identity = {
        'token': 'synthetic-only',
        'expires_at': '2030-01-01T00:00:00Z',
      };

ScrollController bodyScroll(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(
      find
          .descendant(
            of: find.byType(PostListPage),
            matching: find.byType(SingleChildScrollView),
          )
          .first,
    )
    .controller!;

void main() {
  setUpAll(() async {
    for (final (family, path) in [
      ('Microsoft YaHei UI', 'C:/Windows/Fonts/msyh.ttc'),
      (
        'MaterialIcons',
        'C:/codex-tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ),
    ]) {
      await (FontLoader(family)..addFont(
            File(path).readAsBytes().then((v) => ByteData.sublistView(v)),
          ))
          .load();
    }
  });
  setUp(() {
    SecureVault.setMockInitialValues({});
    BrowseCache.shared.directory = null;
  });
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'detail/back restores list offset and route through slow reload at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final site = PositionSite();
        final state = makeApp(site);
        await tester.pumpWidget(XingyuApp(app: state));
        await frames(tester);
        void open(DeskRoute route) =>
            tester.widget<DeskScope>(find.byType(DeskScope).first).open(route);
        for (final route in [
          const DeskRoute('home', '首页'),
          const DeskRoute('rank', '排行', filter: 'weekly', page: 2),
          const DeskRoute('posts', '分类作品', id: 13, page: 2),
          const DeskRoute('search', '搜索', query: '测试作品', page: 2),
          const DeskRoute('favorites', '收藏'),
          const DeskRoute('authorPosts', '作者作品', id: 77),
        ]) {
          open(route);
          await frames(tester);
          final scroll = bodyScroll(tester);
          scroll.jumpTo(700);
          await tester.pump();
          final offset = scroll.offset;
          if (route.kind == 'home') {
            // Carousel storage must not replace the vertical list offset.
            await tester.pump(const Duration(seconds: 6));
            await tester.pump(const Duration(milliseconds: 600));
            expect(scroll.offset, offset);
          }
          // Enter via the actual work card, not a synthetic replacement route.
          await tester.tap(find.byType(PostCard).hitTestable().first);
          await frames(tester);
          expect(find.byType(ArticlePage), findsOneWidget);
          site.paused = Completer<Json>();
          await tester.tap(find.byTooltip(width < 700 ? '返回' : '返回 Alt+←'));
          await frames(tester);
          if (route.kind == 'favorites') {
            expect(find.text('正在载入内容…'), findsOneWidget);
          } else {
            expect(find.byType(LoadingLayout), findsOneWidget);
          }
          site.paused!.complete(site.pendingResult!);
          site.paused = null;
          await frames(tester);
          expect(
            tester.widget<PostListPage>(find.byType(PostListPage)).route.key,
            route.key,
          );
          expect(
            bodyScroll(tester).offset,
            closeTo(offset, 1),
            reason: route.key,
          );
          expect(tester.takeException(), isNull);
        }
        // New pagination/category states begin at their own position.
        open(const DeskRoute('posts', '另一分类', id: 14, page: 3));
        await frames(tester);
        expect(bodyScroll(tester).offset, 0);
        await tester.tap(find.byTooltip(width < 700 ? '返回' : '返回 Alt+←'));
        await frames(tester);
        expect(bodyScroll(tester).offset, closeTo(700, 1));
        state.user = {...FakeSite.user, 'id': 88};
        state.generation++;
        state.notifyListeners();
        await frames(tester);
        expect(bodyScroll(tester).offset, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      },
    );

    testWidgets(
      'top category navigation restores selection, pagination and scroll at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = makeApp(PositionSite())
          ..local = {
            'categoryLayout': {'47': 'tabs'},
            'categoryCursor': {
              '47': {'parent': 12, 'selected': 13, 'page': 2},
            },
          };
        await tester.pumpWidget(XingyuApp(app: app));
        await frames(tester);
        tester
            .widget<DeskScope>(find.byType(DeskScope).first)
            .open(const DeskRoute('categories', '分类'));
        await frames(tester);
        expect(
          tester.widget<PostListPage>(find.byType(PostListPage)).route.id,
          13,
        );
        bodyScroll(tester).jumpTo(500);
        await tester.pump();
        await tester.tap(find.byType(PostCard).hitTestable().first);
        await frames(tester);
        await tester.tap(find.byTooltip(width < 700 ? '返回' : '返回 Alt+←'));
        await frames(tester);
        final restored = tester
            .widget<PostListPage>(find.byType(PostListPage))
            .route;
        expect(restored.id, 13);
        expect(restored.page, 2);
        expect(bodyScroll(tester).offset, closeTo(500, 1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      },
    );

    testWidgets(
      'chat enters and switches at newest message; reading older messages is stable at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = makeApp(PositionSite());
        await tester.pumpWidget(XingyuApp(app: app));
        await frames(tester);
        void open(DeskRoute route) =>
            tester.widget<DeskScope>(find.byType(DeskScope).first).open(route);
        open(const DeskRoute('chat', '聊天室'));
        await frames(tester);
        final chat = tester.widget<ChatPage>(find.byType(ChatPage)).controller!;
        chat.pause();
        Json item(int id, String channel) => {
          'id': id,
          'channel': channel,
          'sender': {'id': 77, 'nickname': '测试同好'},
          'text': '频道$channel 第$id条消息',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        };
        for (var i = 1; i <= 150; i++) {
          chat.rooms['1']!.messages[i] = item(i, '1');
          chat.rooms['2']!.messages[i] = item(i, '2');
        }
        chat.update();
        await frames(tester);
        ScrollController scroll() => tester
            .widget<ListView>(
              find.descendant(
                of: find.byType(ChatPage),
                matching: find.byType(ListView),
              ),
            )
            .controller!;
        expect(scroll().offset, 0);
        expect(find.text('频道1 第150条消息'), findsOneWidget);
        scroll().jumpTo(600);
        await tester.pump();
        chat.room.messages[151] = item(151, '1');
        chat.update();
        await frames(tester);
        expect(scroll().offset, closeTo(600, 1));
        await tester.tap(find.text('频道二'));
        await frames(tester);
        expect(scroll().offset, 0);
        expect(find.text('频道2 第150条消息'), findsOneWidget);
        await tester.tap(find.text('频道一'));
        await frames(tester);
        expect(scroll().offset, 0);
        expect(find.text('频道1 第151条消息'), findsOneWidget);
        scroll().jumpTo(700);
        await tester.pump();
        open(const DeskRoute('mine', '我的'));
        await frames(tester);
        open(const DeskRoute('chat', '聊天室'));
        await frames(tester);
        chat.pause();
        expect(scroll().offset, 0);
        expect(find.text('频道1 第151条消息'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      },
    );
  }
}
