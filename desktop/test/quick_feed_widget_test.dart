import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/app.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/browse_cache.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/quick_feed.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/pages/discovery.dart';
import 'package:xingyu_desktop/pages/quick_feed.dart';
import 'package:xingyu_desktop/ui/shared.dart';

import 'support/system_test_fonts.dart';

const quickTree = <Json>[
  {'id': 10, 'name': '游戏'},
  {'id': 20, 'name': '音声'},
];

class QuickWidgetFixture {
  int generation = 1, reads = 0, infoReads = 0, listReads = 0;
  bool failing = false;
  final history = <Json>[
    {
      'id': 99,
      'title': '已看作品',
      'categories': [
        {'id': 10, 'name': '游戏'},
      ],
    },
  ];

  Json work(int id, {int category = 10}) => {
    'id': id,
    'title': '灵感收藏 $id · 每一场热爱都值得认真珍藏',
    'status': 'publish',
    'thumb': '',
    'created_at': '2026-11-01T00:00:00Z',
    'view_count': 120,
    'user': {'id': 77, 'nickname': '星屿作者'},
    'categories': [
      {'id': category, 'name': category == 10 ? '游戏' : '音声'},
    ],
  };

  Future<Json> get(String path, [Map<String, dynamic>? params]) async {
    reads++;
    if (failing) throw const SocketException('Synthetic offline fixture');
    if (path == 'post/info') {
      infoReads++;
      return {'data': work(number(params?['id']))};
    }
    if (path == 'post/list') listReads++;
    final page = number(params?['page']);
    final category = number(params?['category_in[0]']);
    return {
      'data': List.generate(
        24,
        (i) => work(
          generation * 100000 + category * 1000 + page * 24 + i,
          category: category == 0 ? (i.isEven ? 10 : 20) : category,
        ),
      ),
      'meta': {
        'pagination': {'total_pages': 30},
      },
    };
  }

  QuickFeedStore store() => QuickFeedStore(
    get: get,
    history: () => history,
    categories: () => quickTree,
    account: () => 47,
    random: Random(9),
  );
}

class QuickFixtureSite extends SiteApi {
  final QuickWidgetFixture fixture;
  QuickFixtureSite(this.fixture);
  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) =>
      fixture.get(path, params);
}

class QuickShellSite extends QuickFixtureSite {
  QuickShellSite(super.fixture);
  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) async {
    if (path == 'category/list') return {'data': quickTree};
    if (path == 'comment/list') return {'data': []};
    return super.get(path, params);
  }
}

class QuickShellService extends ServiceApi {
  @override
  Future<Json> request(
    String path, {
    String? token,
    Json? body,
    String? method,
  }) async => {};
}

class QuickOfflineSocket extends SocketConnector {
  @override
  Future<WebSocket> connect(
    String url, {
    Map<String, dynamic>? headers,
  }) async => throw const SocketException('Synthetic offline socket');
}

Future<void> quickCapture(
  WidgetTester tester,
  GlobalKey key,
  int width, {
  String prefix = 'quick-feed',
}) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/$prefix-$width.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    await loadSystemTestFonts();
  });
  setUp(() async {
    SecureVault.setMockInitialValues({});
    BrowseCache.shared.directory = null;
    await BrowseCache.shared.clear();
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets('shell quick feed is between home and categories at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = QuickWidgetFixture();
      final app =
          AppState(
              siteApi: QuickShellSite(fixture),
              serviceApi: QuickShellService(),
              socketFactory: QuickOfflineSocket.new,
            )
            ..starting = false
            ..user = {'id': 47, 'nickname': '测试用户'}
            ..categories = quickTree
            ..local = {
              'history': {'47': fixture.history},
            };
      final shot = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: XingyuApp(app: app).theme(Brightness.light),
          home: RepaintBoundary(key: shot, child: DesktopShell(app)),
        ),
      );
      await tester.pumpAndSettle();
      final home = find.text(width < 700 ? '首页' : '发现').first;
      final quick = find.text('快撸').first, category = find.text('分类').first;
      if (width < 700) {
        expect(tester.getCenter(home).dx, lessThan(tester.getCenter(quick).dx));
        expect(
          tester.getCenter(quick).dx,
          lessThan(tester.getCenter(category).dx),
        );
      } else {
        expect(tester.getCenter(home).dy, lessThan(tester.getCenter(quick).dy));
        expect(
          tester.getCenter(quick).dy,
          lessThan(tester.getCenter(category).dy),
        );
      }
      await tester.tap(quick);
      await tester.pumpAndSettle();
      expect(find.byType(QuickFeedPage), findsOneWidget);
      await quickCapture(
        tester,
        shot,
        width.toInt(),
        prefix: 'quick-feed-shell',
      );
      final controller = tester
          .widget<CustomScrollView>(
            find.byKey(const PageStorageKey('quick-feed-scroll')),
          )
          .controller!;
      controller.jumpTo(700);
      await tester.pumpAndSettle();
      final offset = controller.offset;
      final ids = app.quickFeed.posts.map((p) => p['id']).toList();
      final reads = fixture.listReads;
      await tester.tap(find.byType(PostCard).hitTestable().first);
      await tester.pumpAndSettle();
      expect(find.byType(QuickFeedPage), findsNothing);
      await tester.tap(
        find
            .byIcon(width < 700 ? Icons.arrow_back_rounded : Icons.arrow_back)
            .first,
      );
      await tester.pumpAndSettle();
      final restored = tester
          .widget<CustomScrollView>(
            find.byKey(const PageStorageKey('quick-feed-scroll')),
          )
          .controller!;
      expect(restored.offset, closeTo(offset, 1));
      expect(app.quickFeed.posts.map((p) => p['id']).toList(), ids);
      expect(fixture.listReads, reads);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    });

    testWidgets('quick feed refresh, lazy load and return position at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixture = QuickWidgetFixture(), feed = fixture.store();
      final app = AppState()..user = {'id': 47};
      final bucket = PageStorageBucket(), shot = GlobalKey();
      DeskRoute? opened;
      var article = false;
      late StateSetter setRoute;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Microsoft YaHei UI',
            colorSchemeSeed: violet,
          ),
          home: StatefulBuilder(
            builder: (context, setState) {
              setRoute = setState;
              return DeskScope(
                app: app,
                open: (route) {
                  opened = route;
                  setRoute(() => article = true);
                },
                child: RepaintBoundary(
                  key: shot,
                  child: Scaffold(
                    body: PageStorage(
                      bucket: bucket,
                      child: article
                          ? TextButton(
                              key: const Key('quick-test.back'),
                              onPressed: () => setRoute(() => article = false),
                              child: const Text('返回推荐'),
                            )
                          : QuickFeedPage(feed),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(feed.posts, hasLength(24));
      expect(find.text('游戏'), findsWidgets);
      expect(find.byType(Pagination), findsNothing);
      await quickCapture(tester, shot, width.toInt());

      ScrollController controller() => tester
          .widget<CustomScrollView>(
            find.byKey(const PageStorageKey('quick-feed-scroll')),
          )
          .controller!;
      controller().jumpTo(700);
      await tester.pumpAndSettle();
      final offset = controller().offset;
      final calls = fixture.reads;
      final ids = feed.posts.map((p) => p['id']).toList();
      await tester.tap(find.byType(PostCard).hitTestable().first);
      await tester.pumpAndSettle();
      expect(opened?.kind, 'article');
      await tester.tap(find.byKey(const Key('quick-test.back')));
      await tester.pumpAndSettle();
      expect(controller().offset, closeTo(offset, 1));
      expect(feed.posts.map((p) => p['id']).toList(), ids);
      expect(fixture.reads, calls);

      controller().jumpTo(controller().position.maxScrollExtent - 200);
      await tester.pumpAndSettle();
      expect(feed.posts.length, greaterThan(ids.length));
      expect(fixture.reads, greaterThan(calls));
      expect(feed.posts.map((p) => p['id']).toSet().length, feed.posts.length);

      controller().jumpTo(0);
      await tester.pumpAndSettle();
      final oldIds = feed.posts.map((p) => p['id']).toSet();
      fixture.generation++;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 420));
      await tester.pumpAndSettle();
      expect(feed.posts, hasLength(24));
      expect(
        feed.posts.map((p) => p['id']).toSet().intersection(oldIds),
        isEmpty,
      );
      expect(feed.error, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      feed.dispose();
      app.dispose();
    });
  }

  test(
    'old history enrichment persists and does not refetch on next session',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'xingyu-quick-migrate-',
      );
      final fixture = QuickWidgetFixture();
      final app = AppState(siteApi: QuickFixtureSite(fixture))
        ..user = {'id': 47}
        ..directory = temp
        ..categories = quickTree
        ..local = {
          'history': {
            '47': [
              {'id': 99, 'title': '旧版阅读足迹', 'read_at': '2026-10-31'},
            ],
          },
        };
      AppState? next;
      try {
        await app.quickFeed.load();
        await Future<void>.delayed(Duration.zero);
        await app.persist();
        expect(fixture.infoReads, 1);
        expect(rows(app.history.single['categories']).single['id'], 10);
        final restored = object(
          jsonDecode(await File('${temp.path}/library.json').readAsString()),
        );
        next = AppState(siteApi: QuickFixtureSite(fixture))
          ..user = {'id': 47}
          ..local = restored
          ..categories = quickTree;
        await next.quickFeed.load();
        expect(fixture.infoReads, 1);
        expect(next.quickFeed.preferredCategories.single['name'], '游戏');
        expect(next.history.single['read_at'], '2026-10-31');
        await next.rememberHistoryCategories(88, [
          fixture.work(99, category: 20),
        ]);
        expect(rows(next.history.single['categories']).single['id'], 10);
      } finally {
        next?.dispose();
        app.dispose();
        await temp.delete(recursive: true);
      }
    },
  );

  testWidgets('failed initial quick feed presents a working retry', (
    tester,
  ) async {
    final fixture = QuickWidgetFixture()..failing = true;
    final feed = fixture.store();
    final app = AppState()..user = {'id': 47};
    await tester.pumpWidget(
      MaterialApp(
        home: DeskScope(
          app: app,
          open: (_) {},
          child: Scaffold(body: QuickFeedPage(feed)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('推荐暂时未能加载，请检查网络后重试'), findsOneWidget);
    fixture.failing = false;
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(feed.posts, isNotEmpty);
    expect(find.text('推荐暂时未能加载，请检查网络后重试'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    feed.dispose();
    app.dispose();
  });

  test(
    'new browsing history persists category interests across app sessions',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'xingyu-quick-history-',
      );
      final app = AppState()
        ..user = {'id': 47}
        ..directory = temp;
      try {
        final post = QuickWidgetFixture().work(100);
        await app.addHistory(post);
        final restored = object(
          jsonDecode(await File('${temp.path}/library.json').readAsString()),
        );
        final next = AppState()
          ..user = {'id': 47}
          ..local = restored
          ..categories = quickTree;
        expect(next.history.single['categories'], post['categories']);
        expect(next.quickFeed.interests.keys, contains(10));
        expect(next.quickFeed.preferredCategories.single['name'], '游戏');
        next.dispose();
      } finally {
        app.dispose();
        await temp.delete(recursive: true);
      }
    },
  );
}
