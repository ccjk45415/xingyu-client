import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/app.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/pages/conversation.dart';
import 'package:xingyu_desktop/pages/private.dart';
import 'package:xingyu_desktop/ui/shared.dart';

class OfflineSocket extends SocketConnector {
  @override
  Future<WebSocket> connect(
    String url, {
    Map<String, dynamic>? headers,
  }) async => throw const SocketException('Offline UI fixture');
}

class FakeSite extends SiteApi {
  static final user = <String, dynamic>{
    'id': 47,
    'nickname': '星屿测试用户',
    'avatar': '',
    'description': '把每一种喜欢，都收藏成星光。',
    'level': 6,
    'post_count': 8,
    'favorite_post_count': 12,
    'comment_count': 3,
    'permissions': [
      {'name': 'publish_posts'},
    ],
  };
  static final posts = List.generate(
    8,
    (i) => <String, dynamic>{
      'id': i + 1,
      'title': [
        '星光落下的地方，总会有新的故事',
        '把喜欢的灵感，收藏进小宇宙',
        '每一场热爱，都值得认真珍藏',
        '自在阅读，遇见不一样的心动',
      ][i % 4],
      'thumb': '',
      'user_id': 47,
      'user': user,
      'view_count': 148 + i * 32,
      'status': 'publish',
      'created_at': '2026-10-21T02:00:00Z',
      'categories': [
        {'id': 12, 'name': '灵感收藏'},
      ],
      'content':
          '<h2>在这里，遇见新的故事</h2><p>这是用于布局验证的合成作品，不会写入官网。</p><p>长段落与资源链接会在宽屏阅读区中自然排版。</p>[dlbox title="资源下载" info="这是合成测试资源" link1="示例|https://example.com"][/dlbox]',
      'updated_at': '2026-10-21T02:00:00Z',
    },
  );
  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) async {
    if (path == 'auth/me' || path == 'user/info') {
      return {'code': 0, 'data': user};
    }
    if (path == 'post/info') return {'code': 0, 'data': posts.first};
    if (path == 'category/list') {
      return {
        'code': 0,
        'data': [
          {
            'id': 12,
            'name': '灵感收藏',
            'children': [
              {'id': 13, 'name': '插画'},
              {'id': 14, 'name': '故事'},
            ],
          },
          {
            'id': 21,
            'name': '游戏与音乐',
            'children': [
              {'id': 22, 'name': '游戏'},
              {'id': 23, 'name': '音乐'},
            ],
          },
        ],
      };
    }
    if ([
      'post/list',
      'post/rank',
      'post/search',
      'user/favoritePost',
      'user/post',
    ].contains(path)) {
      return {
        'code': 0,
        'data': posts,
        'meta': {
          'pagination': {'current_page': 1, 'total_pages': 2, 'total': 36},
        },
      };
    }
    if (path == 'comment/list') {
      return {
        'code': 0,
        'data': [
          {
            'id': 21,
            'post_id': 1,
            'user_id': 77,
            'user': {'id': 77, 'nickname': '另一位测试用户'},
            'content': '很高兴在星屿遇见这些故事。',
            'vote_count': 2,
            'children': {'data': []},
            'created_at': '2026-10-21T02:00:00Z',
          },
        ],
      };
    }
    return {'code': 0, 'data': []};
  }

  @override
  Future<Json> post(String path, Json body) async => {'code': 0, 'data': {}};
}

class FakeService extends ServiceApi {
  @override
  Future<Json> request(
    String path, {
    String? token,
    Json? body,
    String? method,
  }) async {
    if (path == '/health') return {'protocol': 3, 'channel_count': 2};
    final peer = {'id': 77, 'nickname': '同好测试用户', 'avatar': ''};
    if (path.startsWith('/dm/v1/peer')) {
      return {'available': true, 'user': peer};
    }
    if (path.startsWith('/dm/v1/messages')) {
      return {
        'peer': peer,
        'messages': [
          {
            'id': 1,
            'sender_id': 77,
            'recipient_id': 47,
            'text': '这份喜欢，也很想与你分享。',
            'created_at': '2026-10-21T02:00:00Z',
          },
          {
            'id': 2,
            'sender_id': 47,
            'recipient_id': 77,
            'text': '在星屿，发现新的心动。',
            'created_at': '2026-10-21T02:01:00Z',
          },
        ],
        'cursor': 2,
        'has_older': false,
        'has_more': false,
      };
    }
    return {'conversations': [], 'users': [], 'data': []};
  }
}

Future<void> frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(
      '${Directory(Directory.current.resolveSymbolicLinksSync()).parent.path}/evidence/$name.png',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        File(
          'C:/codex-tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
        ).readAsBytes().then((b) => ByteData.sublistView(b)),
      );
    await icons.load();
    final file = File('C:/Windows/Fonts/msyh.ttc');
    if (await file.exists()) {
      final loader = FontLoader('Microsoft YaHei UI')
        ..addFont(Future.value(ByteData.sublistView(await file.readAsBytes())));
      await loader.load();
    }
  });
  setUp(() => SecureVault.setMockInitialValues({}));
  testWidgets(
    'verified conversation layouts, reply composer and retained channel drafts',
    (tester) async {
      final app =
          AppState(
              siteApi: FakeSite(),
              serviceApi: FakeService(),
              socketFactory: OfflineSocket.new,
            )
            ..starting = false
            ..user = Map.from(FakeSite.user)
            ..identity = {
              'token': 'c' * 64,
              'user': Map.from(FakeSite.user),
              'expires_at': DateTime.now()
                  .add(const Duration(days: 6))
                  .toIso8601String(),
            };
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: XingyuApp(app: app),
        ),
      );
      await frames(tester);
      final scope = tester.widget<DeskScope>(find.byType(DeskScope));
      scope.open(const DeskRoute('chat', '聊天室'));
      await frames(tester);
      final controller = tester
          .widget<ChatPage>(find.byType(ChatPage))
          .controller!;
      controller.pause();
      controller.ready = true;
      controller.status = '已连接 · 仓库认证 · UID 47';
      final peer = {'id': 77, 'nickname': '同好测试用户', 'avatar': ''};
      final original = {
        'id': 1,
        'channel': '1',
        'sender': peer,
        'text': '欢迎来到频道一，一起聊聊喜欢的作品吧。',
        'created_at': '2026-10-21T02:00:00Z',
      };
      controller.room.messages[1] = original;
      controller.room.messages[2] = {
        'id': 2,
        'channel': '1',
        'sender': FakeSite.user,
        'text': '@同好测试用户(UID:77) 很高兴遇见同好。',
        'mentions': [peer],
        'created_at': '2026-10-21T02:01:00Z',
      };
      controller.room.messages[3] = {
        'id': 3,
        'channel': '1',
        'sender': peer,
        'text': '每一份热爱，都值得被认真回应。',
        'reply_to': {'id': 2, 'sender': FakeSite.user, 'text': '很高兴遇见同好。'},
        'created_at': '2026-10-21T02:02:00Z',
      };
      controller.update();
      await frames(tester);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'desktop-chat');
      await tester.tap(find.text('回复').last);
      await frames(tester);
      expect(find.textContaining('回复 同好测试用户'), findsWidgets);
      controller.room.draft = '还没发送的频道一草稿';
      controller.update();
      scope.open(const DeskRoute('mine', '我的'));
      await frames(tester);
      scope.open(const DeskRoute('chat', '聊天室'));
      await frames(tester);
      expect(
        tester.widget<ChatPage>(find.byType(ChatPage)).controller,
        same(controller),
      );
      expect(controller.room.draft, '还没发送的频道一草稿');
      scope.open(const DeskRoute('dm', '私信', id: 77));
      await frames(tester);
      expect(find.text('同好测试用户'), findsWidgets);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'desktop-private');
      tester.view.physicalSize = const Size(960, 700);
      await frames(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      clearPrivateDrafts();
      await tester.pump(const Duration(seconds: 21));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('login layout, password obscuring, validation and resize', (
    tester,
  ) async {
    final app = AppState(
      siteApi: FakeSite(),
      serviceApi: FakeService(),
      socketFactory: OfflineSocket.new,
    )..starting = false;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: XingyuApp(app: app),
      ),
    );
    await frames(tester);
    expect(find.text('欢迎回到你的小宇宙'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('login.password')))
          .obscureText,
      isTrue,
    );
    await capture(tester, key, 'desktop-login');
    await tester.tap(find.byKey(const Key('login.submit')));
    await tester.pump();
    expect(find.text('请填写账号和密码'), findsOneWidget);

    tester.view.physicalSize = const Size(960, 640);
    await frames(tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
  testWidgets(
    'desktop navigation, reading scrollbar, author UID, forms and responsive widths',
    (tester) async {
      final app =
          AppState(
              siteApi: FakeSite(),
              serviceApi: FakeService(),
              socketFactory: OfflineSocket.new,
            )
            ..starting = false
            ..user = Map.from(FakeSite.user);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: XingyuApp(app: app),
        ),
      );
      await frames(tester);
      expect(find.text('发现新的心动'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'desktop-home');
      final scope = tester.widget<DeskScope>(find.byType(DeskScope));
      for (final route in [
        const DeskRoute('categories', '分类'),
        const DeskRoute('rank', '排行'),
        const DeskRoute('article', '作品详情', id: 1),
        const DeskRoute('author', '作者主页', id: 47),
        const DeskRoute('mine', '我的'),
        const DeskRoute('settings', '设置'),
        const DeskRoute('profile', '编辑个人资料'),
        const DeskRoute('security', '账号安全'),
        const DeskRoute('appearance', '阅读与外观'),
        const DeskRoute('notifications', '通知'),
        const DeskRoute('myComments', '我的评论'),
        const DeskRoute('manage', '投稿与管理'),
        const DeskRoute('editor', '新建投稿'),
        const DeskRoute('chat', '聊天室'),
        const DeskRoute('inbox', '私信'),
      ]) {
        scope.open(route);
        await frames(tester);
        expect(tester.takeException(), isNull, reason: route.kind);
        tester.view.physicalSize = const Size(960, 700);
        await frames(tester);
        expect(tester.takeException(), isNull, reason: 'compact ${route.kind}');
        if (route.kind == 'article') {
          expect(find.byType(Scrollbar), findsWidgets);
        }
        if (route.kind == 'author') {
          expect(find.text('UID  47'), findsOneWidget);
        }
        if (route.kind == 'editor') {
          await capture(tester, key, 'desktop-editor');
        }
        if (route.kind == 'chat') expect(find.text('认证仓库账号'), findsOneWidget);
        tester.view.physicalSize = const Size(1440, 1000);
        await frames(tester);
      }
      scope.open(const DeskRoute('article', '作品详情', id: 1));
      await frames(tester);
      await capture(tester, key, 'desktop-reader');
      await app.setDark(true);
      await frames(tester);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'desktop-reader-dark');
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
