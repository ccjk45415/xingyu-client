import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/browse_cache.dart';
import 'package:xingyu_desktop/core/chat.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/ui/shared.dart';

class SlowSite extends SiteApi {
  int calls = 0;
  Completer<Json> pending = Completer<Json>();
  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) {
    calls++;
    return pending.future;
  }
}

class SlowSocket extends SocketConnector {
  int calls = 0;
  final pending = Completer<WebSocket>();
  @override
  Future<WebSocket> connect(String url, {Map<String, dynamic>? headers}) {
    calls++;
    return pending.future;
  }
}

class HistoryService extends ServiceApi {
  final requests = <String, Completer<Json>>{};
  @override
  Future<Json> request(
    String path, {
    String? token,
    Json? body,
    String? method,
  }) => (requests[path] = Completer<Json>()).future;
}

class SlowProfileApp extends AppState {
  final profile = Completer<void>();
  bool syncing = false;
  SlowProfileApp(HistoryService service, SlowSocket socket)
    : super(serviceApi: service, socketFactory: () => socket);
  @override
  Future<void> syncProfile({bool force = false}) {
    syncing = true;
    return profile.future;
  }
}

void signedIn(AppState app) {
  app.user = {'id': 47};
  app.starting = false;
  app.identity = {
    'token': 'synthetic',
    'user': {'id': 47, 'nickname': '合成账号'},
    'expires_at': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
  };
}

void main() {
  setUp(() async {
    await BrowseCache.shared.clear();
    BrowseCache.shared.enabled = true;
    BrowseCache.shared.directory = await Directory.systemTemp.createTemp(
      'xingyu-loading-',
    );
  });
  tearDown(() async {
    final directory = BrowseCache.shared.directory;
    await BrowseCache.shared.clear();
    BrowseCache.shared.directory = null;
    if (directory != null) await directory.delete(recursive: true);
  });

  test(
    'identical reads share one request; account switches reject late responses',
    () async {
      final site = SlowSite();
      final state = AppState(siteApi: site);
      signedIn(state);
      addTearDown(state.dispose);
      final a = state.get('post/info', {'id': 1});
      final b = state.get('post/info', {'id': 1});
      expect(identical(a, b), true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(site.calls, 1);
      state.user = {'id': 88};
      state.generation++;
      site.pending.complete({
        'data': {'id': 1},
      });
      await expectLater(a, throwsA(isA<ApiFailure>()));
      await expectLater(b, throwsA(isA<ApiFailure>()));
      expect((await BrowseCache.shared.size()).entries, 0);
    },
  );

  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'cached content paints before network, refresh retains content at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = AppState();
        signedIn(app);
        addTearDown(app.dispose);
        await tester.runAsync(
          () =>
              BrowseCache.shared.putJson('pane:v1:47:home', {'title': '已缓存作品'}),
        );
        var pending = Completer<Json>(), calls = 0;
        VoidCallback? refresh;
        await tester.pumpWidget(
          MaterialApp(
            home: DeskScope(
              app: app,
              open: (_) {},
              child: Scaffold(
                body: AsyncPane(
                  cacheKey: 'home',
                  load: () {
                    calls++;
                    return pending.future;
                  },
                  builder: (data, reload) {
                    refresh = reload;
                    return PageBody(
                      child: Column(
                        children: [
                          Text(text(data['title'])),
                          for (var i = 0; i < 30; i++)
                            SizedBox(height: 50, child: Text('行$i')),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        expect(find.text('已缓存作品'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(calls, 1);
        // The first-frame cache is real; keep disk IO outside Flutter's fake clock.
        BrowseCache.shared.enabled = false;
        final pageState = tester.state(find.byType(PageBody));
        pending.complete({'title': '网络新作品'});
        await tester.pump();
        expect(find.text('网络新作品'), findsOneWidget);
        expect(identical(tester.state(find.byType(PageBody)), pageState), true);
        pending = Completer<Json>();
        refresh!();
        await tester.pump();
        expect(find.text('网络新作品'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        pending.completeError(const SocketException('synthetic offline'));
        await tester.pumpAndSettle();
        expect(find.text('网络新作品'), findsOneWidget);
        expect(
          find.text('网络暂不可用，正在显示本机缓存'),
          findsOneWidget,
          reason:
              'calls=$calls texts=${tester.widgetList<Text>(find.byType(Text)).map((w) => w.data).toList()}',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'first visit shows skeleton; late old route cannot overwrite new route',
    (tester) async {
      final app = AppState();
      signedIn(app);
      addTearDown(app.dispose);
      BrowseCache.shared.enabled = false;
      final old = Completer<Json>(), next = Completer<Json>();
      Widget pane(String key, Future<Json> future) => MaterialApp(
        home: DeskScope(
          app: app,
          open: (_) {},
          child: Scaffold(
            body: AsyncPane(
              cacheKey: key,
              load: () => future,
              builder: (data, _) => Text(text(data['title'])),
            ),
          ),
        ),
      );
      await tester.pumpWidget(pane('rank:daily', old.future));
      expect(find.byType(LoadingLayout), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(pane('rank:weekly', next.future));
      old.complete({'title': '过期日榜'});
      await tester.pump();
      expect(find.text('过期日榜'), findsNothing);
      next.complete({'title': '本周榜单'});
      await tester.pump();
      expect(find.text('本周榜单'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'account scope and authorization failure never reveal cached data',
    (tester) async {
      final app = AppState();
      signedIn(app);
      addTearDown(app.dispose);
      await tester.runAsync(
        () =>
            BrowseCache.shared.putJson('pane:v1:47:home', {'title': '账号47缓存'}),
      );
      final pending = Completer<Json>();
      BrowseCache.shared.enabled = false;
      app.user = {'id': 88};
      app.generation++;
      await tester.pumpWidget(
        MaterialApp(
          home: DeskScope(
            app: app,
            open: (_) {},
            child: Scaffold(
              body: AsyncPane(
                cacheKey: 'home',
                load: () => pending.future,
                builder: (data, _) => Text(text(data['title'])),
              ),
            ),
          ),
        ),
      );
      expect(find.text('账号47缓存'), findsNothing);
      pending.completeError(ApiFailure(401, '认证已过期'));
      await tester.pump();
      expect(find.text('认证已过期'), findsOneWidget);
      expect(find.text('账号47缓存'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('chat history and socket start before profile completes; stale channel history ignored', () async {
    final service = HistoryService(), socket = SlowSocket();
    final state = SlowProfileApp(service, socket);
    signedIn(state);
    final chat = ChatController(state);
    final first = chat.start();
    expect(state.syncing, true);
    expect(socket.calls, 1);
    expect(service.requests.length, 1);
    await chat.start();
    expect(socket.calls, 1);
    chat.room.draft = '保留我的输入';
    final second = chat.choose('2');
    service.requests['/v1/channels/1/messages?limit=30']!.complete({
      'messages': [
        {'id': 1, 'channel': '1', 'text': '过期频道一'},
      ],
    });
    service.requests['/v1/channels/2/messages?limit=30']!.complete({
      'messages': [
        {'id': 2, 'channel': '2', 'text': '当前频道二'},
      ],
    });
    await Future<void>.delayed(Duration.zero);
    expect(chat.rooms['1']!.messages, isEmpty);
    expect(chat.room.messages[2]!['text'], '当前频道二');
    expect(chat.rooms['1']!.draft, '保留我的输入');
    expect(chat.ready, false);
    chat.pause();
    socket.pending.completeError(const SocketException('synthetic cancelled'));
    state.profile.complete();
    await Future.wait([first, second]);
    chat.dispose();
    state.dispose();
  });
}
