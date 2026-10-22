import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/category_preferences.dart';
import 'package:xingyu_desktop/pages/discovery.dart';
import 'package:xingyu_desktop/pages/following.dart';
import 'package:xingyu_desktop/pages/account.dart';
import 'package:xingyu_desktop/app.dart';
import 'package:xingyu_desktop/ui/shared.dart';
import 'package:xingyu_desktop/ui/category_filter.dart';

import 'widget_test.dart'
    show FakeSite, FakeService, OfflineSocket, frames, capture;

final tree = <Json>[
  {
    'id': 10,
    'name': '书籍',
    'children': [
      {'id': 11, 'name': '漫画'},
      {'id': 12, 'name': '小说'},
    ],
  },
  {
    'id': 20,
    'name': '游戏',
    'children': [
      {'id': 21, 'name': '电脑游戏'},
      {'id': 22, 'name': '手机游戏'},
    ],
  },
];
Json post(int id, int author, int category, String title) => {
  'id': id,
  'user_id': author,
  'user': {'id': author, 'nickname': '作者$author', 'avatar': ''},
  'title': title,
  'thumb': '',
  'created_at': '2026-10-22T10:00:00Z',
  'categories': [
    {'id': category, 'name': '测试分类'},
  ],
  'view_count': 3,
};

class BrowseSite extends FakeSite {
  final requests = <(String, Map<String, dynamic>)>[];
  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) async {
    requests.add((path, {...?params}));
    if (path == 'category/list') return {'data': tree};
    if (path == 'user/info') {
      return {
        'data': {
          'id': params!['id'],
          'nickname': '官网作者${params['id']}',
          'avatar': '',
        },
      };
    }
    if (path == 'post/list' || path == 'post/rank') {
      return {
        'data': [
          post(1, 77, 11, '已选漫画作品'),
          post(2, 88, 21, '未选游戏作品'),
          post(3, 77, 12, '另一篇小说作品'),
        ],
        'meta': {
          'pagination': {
            'current_page': params?['page'] ?? 1,
            'total_pages': 2,
            'total': 3,
          },
        },
      };
    }
    return super.get(path, params);
  }
}

class FollowService extends FakeService {
  final calls = <String>[];
  final follows = <int>{77};
  final writes = <Json>[];
  Completer<Json>? delay;
  @override
  Future<Json> request(
    String path, {
    String? token,
    Json? body,
    String? method,
  }) async {
    calls.add(path);
    if (!path.startsWith('/dm/v1/follows')) {
      return super.request(path, token: token, body: body, method: method);
    }
    if (delay != null) return delay!.future;
    final u = Uri.parse(path);
    if (body != null) {
      writes.add(body);
      if (body['following'] == true) {
        follows.add(number(body['peer_id']));
      } else {
        follows.remove(number(body['peer_id']));
      }
      return {
        'following': body['following'],
        'following_count': follows.length,
      };
    }
    if (u.path.endsWith('/status')) {
      return {
        'following': follows.contains(
          int.tryParse(u.queryParameters['peer'] ?? '0'),
        ),
        'follows_you': true,
        'following_count': follows.length,
        'follower_count': 1,
      };
    }
    final users = [
      for (final id in follows)
        {
          'id': id,
          'nickname': '作者$id',
          'avatar': '',
          'following': true,
          'follows_you': true,
        },
    ];
    if (u.path.endsWith('/ids')) {
      return {'ids': follows.toList(), 'authors': users};
    }
    return {'users': users, 'total': users.length, 'total_pages': 1};
  }
}

AppState makeApp(BrowseSite site, FollowService service) =>
    AppState(
        siteApi: site,
        serviceApi: service,
        socketFactory: OfflineSocket.new,
      )
      ..starting = false
      ..user = Map.from(FakeSite.user)
      ..categories = tree
      ..identity = {
        'token': 'a' * 64,
        'user': {'id': 47},
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
      final f = File(path);
      if (f.existsSync()) {
        await (FontLoader(
          family,
        )..addFont(f.readAsBytes().then(ByteData.sublistView))).load();
      }
    }
  });
  setUp(() => SecureVault.setMockInitialValues({}));
  test('category branches, excluding child, strict matching and account-scoped preferences', () async {
    final site = BrowseSite(),
        service = FollowService(),
        app = makeApp(site, service);
    final selected = <int>{};
    toggleCategory(selected, tree.first, true, tree);
    expect(selected, {10, 11, 12});
    toggleCategory(selected, rows(tree.first['children']).first, false, tree);
    expect(selected, {12});
    expect(matchesCategories(post(1, 77, 11, 'a'), selected), false);
    expect(matchesCategories(post(1, 77, 12, 'a'), selected), true);
    expect(effectiveCategories({12, 999}, tree), {12});
    await app.setHomeCategories({12});
    await app.setCategoryLayout(true);
    app.user = {...FakeSite.user, 'id': 48};
    expect(app.homeCategories, isNull);
    expect(app.categoryTopNavigation, false);
    app.user = Map.from(FakeSite.user);
    expect(app.homeCategories, {12});
    expect(app.categoryTopNavigation, true);
    await app.setHomeCategories({});
    expect(app.homeCategories, isEmpty);
    app.dispose();
  });
  test('late social failure cannot revoke a newer verified session or cross account boundaries', () async {
    final site = BrowseSite(),
        service = FollowService()..delay = Completer<Json>(),
        app = makeApp(site, service);
    final pending = app.social('/dm/v1/follows/status');
    app.identity = {...app.identity!, 'token': 'b' * 64};
    service.delay!.completeError(ApiFailure(401, 'old token'));
    await expectLater(pending, throwsA(isA<ApiFailure>()));
    expect(app.token, 'b' * 64);
    service.delay = Completer<Json>();
    final old = app.social('/dm/v1/follows/ids');
    app.user = {'id': 48};
    app.generation++;
    service.delay!.complete({
      'ids': [77],
    });
    await expectLater(old, throwsA(isA<ApiFailure>()));
    app.dispose();
  });
  for (final width in [1280.0, 430.0]) {
    testWidgets('home filter UI, query and strict results $width', (
      tester,
    ) async {
      final site = BrowseSite(), app = makeApp(site, FollowService());
      final shot = GlobalKey();
      DeskRoute? opened;
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> pump(Widget child) async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: shot,
            child: MaterialApp(
              theme: ThemeData(fontFamily: 'Microsoft YaHei UI'),
              home: DeskScope(
                app: app,
                open: (r) => opened = r,
                child: Scaffold(body: child),
              ),
            ),
          ),
        );
        await frames(tester);
      }

      await pump(const HomeFilterBar());
      await tester.tap(find.text('筛选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('清空选择'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, '漫画'));
      await tester.pumpAndSettle();
      await capture(tester, shot, 'desktop-home-filter-${width.toInt()}');
      await tester.tap(find.text('保存筛选'));
      await tester.pumpAndSettle();
      expect(app.homeCategories, {11});
      expect(opened!.page, 1);
      await pump(const PostListPage(DeskRoute('home', '发现')));
      await tester.pumpAndSettle();
      expect(find.text('已选漫画作品'), findsOneWidget);
      expect(find.text('未选游戏作品'), findsNothing);
      expect(find.text('另一篇小说作品'), findsNothing);
      expect(
        site.requests
            .where((r) => r.$1 == 'post/list')
            .last
            .$2['category_in[0]'],
        11,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
      await app.setHomeCategories({});
      site.requests.clear();
      await pump(const PostListPage(DeskRoute('home', '发现')));
      await tester.pumpAndSettle();
      expect(site.requests.where((r) => r.$1 == 'post/list'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
      app.dispose();
    });
    testWidgets(
      'category tabs stay above scrolling posts and retain pagination $width',
      (tester) async {
        final site = BrowseSite(), app = makeApp(site, FollowService());
        await app.setCategoryLayout(true);
        final shot = GlobalKey();
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Microsoft YaHei UI'),
            home: DeskScope(
              app: app,
              open: (_) {},
              child: RepaintBoundary(
                key: shot,
                child: const Scaffold(body: CategoryPage()),
              ),
            ),
          ),
        );
        await frames(tester);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, '游戏'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ChoiceChip, '手机游戏'));
        await tester.pumpAndSettle();
        expect(
          site.requests
              .where((r) => r.$1 == 'post/list')
              .last
              .$2['category_in[0]'],
          22,
        );
        final top = tester.getTopLeft(find.widgetWithText(ChoiceChip, '游戏')).dy;
        await capture(tester, shot, 'desktop-category-tabs-${width.toInt()}');
        final next = find.widgetWithText(OutlinedButton, '下一页');
        expect(next, findsOneWidget);
        {
          await tester.ensureVisible(next);
          await tester.tap(next);
          await tester.pumpAndSettle();
          expect(
            site.requests.where((r) => r.$1 == 'post/list').last.$2['page'],
            2,
          );
        }
        expect(
          tester.getTopLeft(find.widgetWithText(ChoiceChip, '游戏')).dy,
          top,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      },
    );
    testWidgets(
      'following feed filters all authors, author switch and follow control $width',
      (tester) async {
        final site = BrowseSite(),
            service = FollowService(),
            app = makeApp(site, service);
        final shot = GlobalKey();
        DeskRoute route = const DeskRoute('followingFeed', '动态');
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Microsoft YaHei UI'),
            home: StatefulBuilder(
              builder: (c, change) => DeskScope(
                app: app,
                open: (r) => change(() => route = r),
                child: RepaintBoundary(
                  key: shot,
                  child: Scaffold(
                    body: FollowingFeedPage(route, key: ValueKey(route.key)),
                  ),
                ),
              ),
            ),
          ),
        );
        await frames(tester);
        await tester.pumpAndSettle();
        expect(find.text('已选漫画作品'), findsOneWidget);
        expect(find.text('另一篇小说作品'), findsOneWidget);
        expect(find.text('未选游戏作品'), findsNothing);
        expect(site.requests.where((r) => r.$1 == 'post/list').length, 2);
        await capture(tester, shot, 'desktop-following-feed-${width.toInt()}');
        await tester.tap(find.text('作者77').first);
        await tester.pumpAndSettle();
        expect(
          site.requests.where((r) => r.$1 == 'post/list').last.$2['user_id'],
          77,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: DeskScope(
              app: app,
              open: (_) {},
              child: const Scaffold(body: Center(child: FollowButton(77))),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('互相关注'), findsOneWidget);
        await tester.tap(find.text('互相关注'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '取消关注'));
        await tester.pumpAndSettle();
        expect(service.follows, isEmpty);
        expect(service.writes.last, {'peer_id': 77, 'following': false});
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      },
    );
  }
  testWidgets('appearance choice, follows/fans views and navigation order', (
    tester,
  ) async {
    final site = BrowseSite(),
        service = FollowService(),
        app = makeApp(site, service);
    final shot = GlobalKey();
    DeskRoute? opened;
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<void> page(Widget widget) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Microsoft YaHei UI'),
          home: AnimatedBuilder(
            animation: app,
            builder: (_, _) => DeskScope(
              app: app,
              open: (r) => opened = r,
              child: RepaintBoundary(
                key: shot,
                child: Scaffold(body: widget),
              ),
            ),
          ),
        ),
      );
      await frames(tester);
      await tester.pumpAndSettle();
    }

    await page(const SettingsPage('appearance'));
    await tester.tap(find.widgetWithText(ChoiceChip, '顶部双层导航'));
    await tester.pumpAndSettle();
    expect(app.categoryTopNavigation, true);
    await capture(tester, shot, 'desktop-category-layout-settings');
    await page(
      const FollowPeoplePage(
        DeskRoute('followPeople', '我的粉丝', filter: 'followers'),
      ),
    );
    expect(find.text('官网作者77'), findsOneWidget);
    expect(
      service.calls.where((p) => p.startsWith('/dm/v1/follows/status?')),
      isEmpty,
    );
    expect(find.text('互相关注'), findsOneWidget);
    await capture(tester, shot, 'desktop-follow-people');
    await page(const FollowStats());
    expect(find.text('关注'), findsOneWidget);
    expect(find.text('粉丝'), findsOneWidget);
    await tester.tap(find.text('粉丝'));
    expect(opened!.filter, 'followers');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Microsoft YaHei UI'),
        home: DesktopShell(app),
      ),
    );
    await frames(tester);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('聊天室')).dy,
      lessThan(tester.getTopLeft(find.text('动态')).dy),
    );
    expect(
      tester.getTopLeft(find.text('动态')).dy,
      lessThan(tester.getTopLeft(find.text('我的')).dy),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    app.dispose();
  });
  testWidgets('six navigation entries fit short desktop windows', (
    tester,
  ) async {
    final app = makeApp(BrowseSite(), FollowService());
    final shot = GlobalKey();
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [const Size(1280, 640), const Size(960, 640)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        RepaintBoundary(
          key: shot,
          child: XingyuApp(app: app),
        ),
      );
      await frames(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('动态'), findsOneWidget);
      expect(find.byTooltip('我的'), findsOneWidget);
      await capture(
        tester,
        shot,
        'desktop-social-navigation-${size.width.toInt()}',
      );
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
    app.dispose();
  });
  testWidgets(
    'unverified social view has a gate and never reads protected data',
    (tester) async {
      final site = BrowseSite(),
          service = FollowService(),
          app = makeApp(site, service)..identity = null;
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
      expect(find.text('认证仓库账号'), findsOneWidget);
      expect(service.calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
