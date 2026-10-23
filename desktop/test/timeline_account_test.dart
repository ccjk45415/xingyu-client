import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/app.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/following_feed.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/pages/account.dart';
import 'package:xingyu_desktop/pages/following.dart';
import 'package:xingyu_desktop/ui/shared.dart';

import 'widget_test.dart' show FakeSite, OfflineSocket, frames, capture;
import 'browse_social_test.dart' show FollowService;

class TimelineSite extends FakeSite {
  final requested = <int>[];
  Completer<Json>? pause;
  bool fail = false;
  bool emptyFirst = false;
  Json result(int page) => {
    'data': [
      for (var i = 1; i <= (emptyFirst && page <= 3 ? 0 : 2); i++)
        {
          'id': page == 4 && i == 2 ? 11 : page * 10 + i,
          'user_id': 77,
          'user': {'id': 77, 'nickname': '关注作者', 'avatar': ''},
          'title': '动态作品 $page-$i',
          'thumb': '',
          'created_at': DateTime.utc(
            2026,
            10,
            23,
          ).subtract(Duration(minutes: page * 10 + i)).toIso8601String(),
        },
    ],
    'meta': {
      'pagination': {'total_pages': 6},
    },
  };
  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) async {
    if (path != 'post/list') return super.get(path, params);
    final page = number(params!['page']);
    requested.add(page);
    if (page == 4 && fail) throw ApiFailure(503, 'synthetic offline');
    if (page == 4 && pause != null) return pause!.future;
    return result(page);
  }
}

AppState appFor(TimelineSite site) =>
    AppState(
        siteApi: site,
        serviceApi: FollowService(),
        socketFactory: OfflineSocket.new,
      )
      ..starting = false
      ..user = {...FakeSite.user}
      ..identity = {
        'token': 'synthetic-timeline-user',
        'expires_at': '2030-01-01T00:00:00Z',
      };

void main() {
  setUpAll(() async {
    for (final (family, path) in [
      ('Microsoft YaHei UI', 'C:/Windows/Fonts/msyh.ttc'),
      (
        'MaterialIcons',
        'C:/codex-tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ),
    ]) {
      final font = FontLoader(
        family,
      )..addFont(File(path).readAsBytes().then((v) => ByteData.sublistView(v)));
      await font.load();
    }
  });
  setUp(() => SecureVault.setMockInitialValues({}));

  test('append keeps prefix, removes duplicate/invalid/unfollowed posts and advances cursor', () {
    final old = <Json>[
      {'id': 1, 'user_id': 77},
      {'id': 2, 'user_id': 88},
    ];
    final merged = appendFollowingWindow(
      {'posts': old},
      {
        'ids': [77],
        'selected': 0,
        'next_page': 7,
        'has_more': true,
        'posts': [
          {'id': 1, 'user_id': 77},
          {
            'id': 3,
            'user': {'id': 77},
          },
          {'id': 0, 'user_id': 77},
        ],
      },
    );
    expect(rows(merged['posts']).map((p) => p['id']), [1, 3]);
    expect(merged['next_page'], 7);
    expect(old.length, 2);
  });
  test('timeline cache preserves cursor/offset and is cleared by follow/account invalidation', () {
    final store = FollowingFeedStore(
      get: (_, [p]) async => {},
      social: (_) async => {},
      active: () => true,
    );
    store.rememberTimeline(77, {
      'posts': [
        {'id': 1},
      ],
      'next_page': 4,
    }, 250);
    expect(store.timelineOffset(77), 250);
    expect(store.timeline(77)!['next_page'], 4);
    expect(store.timelineFresh(77), true);
    store.clear();
    expect(store.timeline(77), null);
    expect(store.timelineOffset(77), 0);
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'infinite timeline appends without navigation, retains offset and restores on return $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final site = TimelineSite(),
            app = appFor(site),
            navigated = <DeskRoute>[];
        final shot = GlobalKey();
        Future<void> showFeed() async {
          await tester.pumpWidget(
            MaterialApp(
              theme: XingyuApp(app: app).theme(Brightness.light),
              home: DeskScope(
                app: app,
                open: navigated.add,
                child: RepaintBoundary(
                  key: shot,
                  child: const Scaffold(
                    body: FollowingFeedPage(DeskRoute('followingFeed', '动态')),
                  ),
                ),
              ),
            ),
          );
          await frames(tester);
          await tester.pumpAndSettle();
        }

        await showFeed();
        expect(site.requested, [1, 2, 3]);
        expect(find.text('继续查找更早动态'), findsNothing);
        final view = tester.widget<CustomScrollView>(
              find.byKey(const Key('following.timeline')),
            ),
            scroll = view.controller!;
        site.pause = Completer<Json>();
        scroll.jumpTo(scroll.position.maxScrollExtent - 50);
        await frames(tester);
        expect(find.text('正在加载更多动态…'), findsOneWidget);
        final before = scroll.offset;
        scroll.jumpTo(before - 5);
        scroll.jumpTo(before);
        expect(site.requested.where((p) => p == 4).length, 1);
        expect(navigated, isEmpty);
        site.pause!.complete(site.result(4));
        await frames(tester);
        await tester.pumpAndSettle();
        final timeline = app.followingFeed.timeline(0)!;
        expect(rows(timeline['posts']).length, 11);
        expect(rows(timeline['posts']).take(6).map((p) => p['id']), [
          11,
          12,
          21,
          22,
          31,
          32,
        ]);
        expect(timeline['next_page'], 7);
        expect(timeline['has_more'], false);
        expect(scroll.offset, closeTo(before, 1));
        expect(navigated, isEmpty);
        await capture(tester, shot, 'timeline-append-${width.toInt()}');
        final count = site.requested.length;
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await showFeed();
        final restored = tester
            .widget<CustomScrollView>(
              find.byKey(const Key('following.timeline')),
            )
            .controller!;
        expect(restored.offset, closeTo(before, 1));
        expect(site.requested.length, count);
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      },
    );
  }

  testWidgets(
    'failed append keeps cards and cursor, then retry appends exactly once',
    (tester) async {
      final site = TimelineSite(), app = appFor(site);
      await tester.pumpWidget(
        MaterialApp(
          home: DeskScope(
            app: app,
            open: (_) {},
            child: const Scaffold(
              body: FollowingFeedPage(DeskRoute('followingFeed', '动态')),
            ),
          ),
        ),
      );
      await frames(tester);
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<CustomScrollView>(find.byKey(const Key('following.timeline')))
          .controller!;
      site.fail = true;
      scroll.jumpTo(scroll.position.maxScrollExtent - 1);
      await frames(tester);
      await tester.pumpAndSettle();
      expect(find.text('加载失败，点击重试'), findsOneWidget);
      expect(rows(app.followingFeed.timeline(0)!['posts']).length, 6);
      site.fail = false;
      await tester.ensureVisible(find.text('加载失败，点击重试'));
      await tester.tap(find.text('加载失败，点击重试'));
      await frames(tester);
      await tester.pumpAndSettle();
      expect(rows(app.followingFeed.timeline(0)!['posts']).length, 11);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'sparse timeline continues by upward gesture without a next-page button',
    (tester) async {
      final site = TimelineSite()..emptyFirst = true, app = appFor(site);
      final navigated = <DeskRoute>[];
      await tester.pumpWidget(
        MaterialApp(
          home: DeskScope(
            app: app,
            open: navigated.add,
            child: const Scaffold(
              body: FollowingFeedPage(DeskRoute('followingFeed', '动态')),
            ),
          ),
        ),
      );
      await frames(tester);
      await tester.pumpAndSettle();
      expect(find.text('近期暂未发现投稿'), findsOneWidget);
      expect(site.requested, [1, 2, 3]);
      await tester.drag(
        find.byKey(const Key('following.timeline')),
        const Offset(0, -400),
      );
      await frames(tester);
      await tester.pumpAndSettle();
      expect(site.requested, [1, 2, 3, 4, 5, 6]);
      expect(rows(app.followingFeed.timeline(0)!['posts']).length, 6);
      expect(navigated, isEmpty);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets('late append cannot contaminate a replacement account', (
    tester,
  ) async {
    final site = TimelineSite(), app = appFor(site);
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: app,
          builder: (_, _) => DeskScope(
            app: app,
            open: (_) {},
            child: const Scaffold(
              body: FollowingFeedPage(DeskRoute('followingFeed', '动态')),
            ),
          ),
        ),
      ),
    );
    await frames(tester);
    await tester.pumpAndSettle();
    site.pause = Completer<Json>();
    final scroll = tester
        .widget<CustomScrollView>(find.byKey(const Key('following.timeline')))
        .controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent - 1);
    await frames(tester);
    app.user = {...app.user!, 'id': 88};
    app.generation++;
    app.socialChanged();
    await frames(tester);
    site.pause!.complete({
      'data': [
        {'id': 9999, 'user_id': 77, 'title': '旧账号晚到的动态'},
      ],
      'meta': {
        'pagination': {'total_pages': 4},
      },
    });
    await frames(tester);
    await tester.pumpAndSettle();
    expect(
      rows(app.followingFeed.timeline(0)!['posts']).map((p) => p['id']),
      isNot(contains(9999)),
    );
    expect(find.text('旧账号晚到的动态'), findsNothing);
    expect(tester.takeException(), null);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  for (final width in [360.0, 1280.0]) {
    testWidgets(
      'compact personal center retains every shortcut and responsive layout $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 860);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = appFor(TimelineSite()),
            opened = <DeskRoute>[],
            shot = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: XingyuApp(app: app).theme(Brightness.light),
            home: DeskScope(
              app: app,
              open: opened.add,
              child: RepaintBoundary(
                key: shot,
                child: const Scaffold(
                  body: AccountPage(DeskRoute('mine', '我的')),
                ),
              ),
            ),
          ),
        );
        await frames(tester);
        await tester.pumpAndSettle();
        expect(find.text('我的星屿'), findsNothing);
        expect(
          tester.getBottomLeft(find.byKey(const Key('account.new-post'))).dy,
          lessThan(550),
        );
        for (final item in [
          'favorites',
          'history',
          'myComments',
          'inbox',
          'manage',
          'drafts',
          'logs',
        ]) {
          await tester.tap(find.byKey(ValueKey('account.shortcut.$item')));
          expect(opened.last.kind, item);
        }
        await tester.tap(find.text('关注').last);
        expect(opened.last.filter, 'following');
        await tester.tap(find.text('粉丝').last);
        expect(opened.last.filter, 'followers');
        await tester.tap(find.byKey(const Key('account.new-post')));
        expect(opened.last.kind, 'editor');
        expect(tester.takeException(), null);
        await capture(tester, shot, 'account-compact-${width.toInt()}');
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      },
    );
  }
}
