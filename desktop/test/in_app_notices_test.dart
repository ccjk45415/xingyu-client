import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/app.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/pages/notification_settings.dart';
import 'package:xingyu_desktop/ui/shared.dart';

import 'widget_test.dart'
    show FakeSite, FakeService, OfflineSocket, frames, capture;

class NoticeSite extends FakeSite {
  List<Json> replies = [], votes = [];
  Completer<Json>? paused;
  int reads = 0;
  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) async {
    if (path == 'user/notification') {
      reads++;
      return paused?.future ??
          {'data': params?['action'] == 'vote' ? votes : replies};
    }
    return super.get(path, params);
  }
}

class NoticeService extends FakeService {
  List<Json> conversations = [];
  final Map<String, List<Json>> messages = {'1': [], '2': []};
  int reads = 0;
  bool failDm = false;
  @override
  Future<Json> request(
    String path, {
    String? token,
    Json? body,
    String? method,
  }) async {
    if (path == '/dm/v1/conversations') {
      reads++;
      if (failDm) throw const SocketException('synthetic');
      return {'conversations': conversations};
    }
    if (path.startsWith('/v1/channels/')) {
      reads++;
      final uri = Uri.parse(path), selected = uri.pathSegments[2];
      final before = number(uri.queryParameters['before']);
      final after = number(uri.queryParameters['after']);
      final all =
          messages[selected]!
              .where(
                (m) =>
                    number(m['id']) > after &&
                    (before == 0 || number(m['id']) < before),
              )
              .toList()
            ..sort((a, b) => number(b['id']).compareTo(number(a['id'])));
      return {
        'channel': selected,
        'messages': all.take(30).toList().reversed.toList(),
        'has_older': all.length > 30,
      };
    }
    return super.request(path, token: token, body: body, method: method);
  }
}

Json chatMessage(
  int id, {
  String channel = '1',
  int sender = 77,
  bool mention = true,
  bool reply = false,
}) => {
  'id': id,
  'channel': channel,
  'sender': {'id': sender, 'nickname': '同好'},
  'text': '私密测试内容 $id',
  'mentions': [
    if (mention) {'id': 47},
  ],
  if (reply)
    'reply_to': {
      'sender': {'id': 47},
    },
};
Json replyMessage(String id, {bool post = true, bool read = false}) => {
  'id': id,
  'read_at': read ? '2026-10-24T00:00:00Z' : null,
  'subject_type': post ? 'post' : 'comment',
  'subject': post ? {'id': 123, 'title': '作品'} : {'id': 4, 'post_id': 123},
  'user': {'id': 77, 'nickname': '同好'},
  'causer': {'content': '<p>私密回复内容</p>'},
};
Json conversation(int id) => {
  'peer': {'id': 77, 'nickname': '同好'},
  'unread': 1,
  'last_message': {
    'id': id,
    'sender_id': 77,
    'recipient_id': 47,
    'text': '私密私信内容',
  },
};
AppState makeApp(NoticeSite site, NoticeService service) =>
    AppState(
        siteApi: site,
        serviceApi: service,
        socketFactory: OfflineSocket.new,
      )
      ..starting = false
      ..user = {...FakeSite.user}
      ..identity = {
        'token': 'synthetic-only',
        'expires_at': '2030-01-01T00:00:00Z',
      };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NoticeSite site;
  late NoticeService service;
  late AppState app;
  setUp(() {
    SecureVault.setMockInitialValues({});
    site = NoticeSite();
    service = NoticeService();
    app = makeApp(site, service);
  });
  tearDown(() => app.dispose());

  test('first activation seeds history; new replies, likes, DM and mentions deduplicate', () async {
    site.replies = [replyMessage('old')];
    service.conversations = [conversation(1)];
    service.messages['1'] = [chatMessage(1)];
    await app.notices.refresh();
    expect(app.notices.entries, isEmpty);
    site.replies.insertAll(0, [
      replyMessage('post'),
      replyMessage('comment', post: false),
      replyMessage('read', read: true),
    ]);
    site.votes = [replyMessage('like')];
    service.conversations = [conversation(2)];
    service.messages['1']!.addAll([
      chatMessage(2),
      chatMessage(3, sender: 47),
      chatMessage(4, mention: false),
    ]);
    await app.notices.refresh();
    expect(app.notices.entries.map((e) => e.kind).toSet(), {
      'dm',
      'chatMention',
      'postReply',
      'commentReply',
      'like',
    });
    expect(app.notices.unread, 5);
    final post = app.notices.entries.firstWhere((e) => e.kind == 'postReply');
    expect(noticeRoute(post).id, 123);
    expect(
      noticeRoute(app.notices.entries.firstWhere((e) => e.kind == 'dm')).id,
      77,
    );
    expect(
      noticeRoute(
        app.notices.entries.firstWhere((e) => e.kind == 'chatMention'),
      ).filter,
      '1',
    );
    await app.notices.refresh();
    expect(app.notices.entries.length, 5);
    expect(jsonEncode(app.local), isNot(contains('私密')));
    app.notices.readAll();
    expect(app.notices.unread, 0);
    expect(app.notices.banner, isNull);
  });
  test('foreground socket mention, viewing suppression and chat replies', () {
    app.notices.route = 'chat';
    app.notices.channel = '1';
    app.notices.acceptChat(chatMessage(1), '1');
    expect(app.notices.unread, 0);
    expect(app.notices.banner, isNull);
    app.notices.acceptChat(
      chatMessage(2, channel: '2', mention: false, reply: true),
      '2',
    );
    expect(app.notices.unread, 1);
    expect(app.notices.banner!.title, contains('回复'));
    app.notices.acceptChat(chatMessage(2, channel: '2'), '2');
    expect(app.notices.entries.length, 2);
  });
  test(
    'disabled sources make no calls; settings isolated by account and persist',
    () async {
      await app.notices.setPreference('dm', false);
      await app.notices.setPreference('postReply', false);
      await app.notices.refresh();
      service.conversations = [conversation(2)];
      site.replies = [replyMessage('p')];
      await app.notices.refresh();
      expect(app.notices.entries, isEmpty);
      await app.notices.setPreference('enabled', false);
      final calls = site.reads + service.reads;
      await app.notices.refresh();
      expect(site.reads + service.reads, calls);
      app.user = {...FakeSite.user, 'id': 99};
      app.generation++;
      expect(app.notices.enabledAll, true);
      expect(app.notices.enabled('dm'), true);
      app.user = {...FakeSite.user};
      app.generation++;
      expect(app.notices.enabledAll, false);
      expect(app.notices.enabled('dm'), false);
    },
  );
  test('late account responses, background pause and overlapping checks are ignored', () async {
    await app.notices.refresh();
    site.paused = Completer<Json>();
    final flight = app.notices.refresh();
    final calls = site.reads;
    await app.notices.refresh();
    expect(site.reads, calls);
    app.notices.pause();
    site.paused!.complete({
      'data': [replyMessage('late')],
    });
    await flight;
    expect(app.notices.entries, isEmpty);
    final allCalls = site.reads + service.reads;
    await app.notices.refresh();
    app.notices.acceptChat(chatMessage(9), '1');
    expect(site.reads + service.reads, allCalls);
    expect(app.notices.entries, isEmpty);
  });
  test('changing account before pending response cannot create a cross-account notice', () async {
    await app.notices.refresh();
    site.paused = Completer<Json>();
    final pending = app.notices.refresh();
    app.user = {...FakeSite.user, 'id': 99};
    app.generation++;
    site.paused!.complete({
      'data': [replyMessage('late')],
    });
    await pending;
    expect(app.notices.entries, isEmpty);
    expect(object(app.local['inAppNoticeSeen']).containsKey('99'), false);
  });
  test('busy channels drain older pages on subsequent polls without dropping mentions', () async {
    await app.notices.refresh();
    service.messages['1'] = [
      for (var i = 1; i <= 120; i++)
        chatMessage(i, mention: i == 2 || i == 118),
    ];
    await app.notices.refresh();
    expect(app.notices.entries.where((e) => e.key == 'chat:1:118').length, 1);
    await app.notices.refresh();
    expect(app.notices.entries.where((e) => e.key == 'chat:1:2').length, 1);
    expect(
      number(object(object(app.local['inAppNoticeSeen'])['47'])['chat:1']),
      120,
    );
    await app.notices.refresh();
    expect(app.notices.unread, 2);
  });
  test(
    'one failed source does not discard other reminders or advance its cursor',
    () async {
      await app.notices.refresh();
      service.failDm = true;
      site.replies = [replyMessage('new')];
      await app.notices.refresh();
      expect(app.notices.entries.single.kind, 'postReply');
      expect(app.notices.status, contains('暂未同步'));
      service.failDm = false;
      service.conversations = [conversation(9)];
      await app.notices.refresh();
      expect(app.notices.entries.any((e) => e.kind == 'dm'), true);
      expect(app.notices.status, isNot(contains('暂未同步')));
    },
  );

  setUpAll(() async {
    final flutterRoot =
        Platform.environment['FLUTTER_ROOT'] ?? 'C:/codex-tools/flutter';
    for (final (family, path) in [
      ('Microsoft YaHei UI', 'C:/Windows/Fonts/msyh.ttc'),
      (
        'MaterialIcons',
        '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ),
    ]) {
      if (!await File(path).exists()) continue;
      await (FontLoader(family)..addFont(
            File(path).readAsBytes().then((v) => ByteData.sublistView(v)),
          ))
          .load();
    }
  });
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'notification settings, private preview and channel jump at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
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
        void open(DeskRoute route) =>
            tester.widget<DeskScope>(find.byType(DeskScope).first).open(route);
        open(const DeskRoute('noticeSettings', '通知设置'));
        await frames(tester);
        expect(find.byType(NotificationSettingsPage), findsOneWidget);
        expect(find.text('开启应用内提醒'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(tester, key, 'notifications-settings-${width.round()}');
        open(const DeskRoute('home', '首页'));
        await frames(tester);
        app.notices.acceptChat(chatMessage(999, channel: '2'), '2');
        await frames(tester);
        expect(find.textContaining('艾特了你'), findsOneWidget);
        expect(find.textContaining('私密测试内容'), findsNothing);
        await capture(tester, key, 'notifications-banner-${width.round()}');
        await tester.tap(find.textContaining('艾特了你'));
        await frames(tester);
        expect(app.notices.channel, '2');
        expect(app.notices.banner, isNull);
        expect(app.notices.unread, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 21));
      },
    );
  }
}
