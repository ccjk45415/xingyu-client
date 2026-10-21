import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/pages/discovery.dart';
import 'package:xingyu_desktop/ui/shared.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/home_content.dart';

class HomeWire extends Stream<dynamic> implements WebSocket {
  final events = StreamController<dynamic>();
  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => events.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  void add(dynamic data) {}
  @override
  Future<void> close([int? code, String? reason]) async {
    unawaited(events.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class HomeConnector extends SocketConnector {
  final HomeWire wire;
  String? requested;
  HomeConnector(this.wire);
  @override
  Future<WebSocket> connect(String url, {Map<String, dynamic>? headers}) async {
    requested = url;
    return wire;
  }
}

class BrokenHomeConnector extends SocketConnector {
  @override
  Future<WebSocket> connect(
    String url, {
    Map<String, dynamic>? headers,
  }) async => throw const SocketException('local offline fixture');
}

class HomeService extends ServiceApi {
  final Json snapshot;
  HomeService(this.snapshot);
  @override
  Future<Json> request(
    String path, {
    String? token,
    Json? body,
    String? method,
  }) async {
    expect(path, '/announcements');
    return snapshot;
  }
}

Json noticeSnapshot(int revision, String title, {Json? discovery}) => {
  'schema': 1,
  'revision': revision,
  'updated_at': revision == 0 ? null : '2026-10-22T09:00:00Z',
  'items': [
    {'id': 'cached', 'title': title, 'content': '公告正文'},
  ],
  'discovery': ?discovery,
};
Future<void> mountHome(WidgetTester tester, AppState app) async {
  await tester.pumpWidget(
    MaterialApp(
      home: DeskScope(
        app: app,
        open: (_) {},
        child: const Scaffold(body: HomeBanner()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  test('default discovery and old announcement payload remain valid', () {
    expect(validDiscovery(defaultDiscovery), isNotNull);
    final old = {'schema': 1, 'revision': 0, 'updated_at': null, 'items': []};
    expect(validAnnouncements(old), isNotNull);
    expect(
      validAnnouncements({...old, 'discovery': defaultDiscovery}),
      isNotNull,
    );
  });
  test('remote content validates Unicode, fields, timestamp and revision', () {
    expect(
      validDiscovery({...defaultDiscovery, 'title': '😀' * 80}),
      isNotNull,
    );
    for (final invalid in [
      {...defaultDiscovery, 'title': '😀' * 81},
      {...defaultDiscovery, 'content': '\u0000'},
      {...defaultDiscovery, 'revision': -1},
      {...defaultDiscovery, 'revision': 0.5},
      {...defaultDiscovery, 'revision': 1, 'updated_at': 'invalid'},
    ]) {
      expect(validDiscovery(invalid), isNull);
    }
    expect(
      validDiscovery({
        ...defaultDiscovery,
        'revision': 1,
        'updated_at': '2026-10-22T09:00:00Z',
      }),
      isNotNull,
    );
  });
  testWidgets(
    'home starts with announcement and accepts live discovery with independent revision without refresh',
    (tester) async {
      final wire = HomeWire();
      final liveConnector = HomeConnector(wire);
      final app = AppState(socketFactory: () => liveConnector);
      app.local['announcements'] = noticeSnapshot(4, '缓存公告');
      app.local['discovery'] = {
        ...defaultDiscovery,
        'revision': 1,
        'updated_at': '2026-10-22T09:00:00Z',
        'title': '缓存发现',
      };
      await mountHome(tester, app);
      expect(find.text('星屿公告栏').hitTestable(), findsOneWidget);
      expect(find.text('缓存公告').hitTestable(), findsOneWidget);
      expect(liveConnector.requested, endsWith('/announcements/live'));
      final remote = {
        ...defaultDiscovery,
        'revision': 2,
        'updated_at': '2026-10-22T09:01:00Z',
        'title': '即时发现',
        'content': '不用更新客户端的最新正文',
      };
      wire.events.add(
        jsonEncode({
          'type': 'announcements',
          'data': noticeSnapshot(3, '旧公告', discovery: remote),
        }),
      );
      await tester.pump();
      await tester.pump();
      expect(app.local['announcements']['revision'], 4);
      expect(app.local['discovery']['title'], '即时发现');
      await tester.drag(find.byType(PageView), const Offset(-700, 0));
      await tester.pumpAndSettle();
      expect(find.text('即时发现').hitTestable(), findsOneWidget);
      expect(find.text('不用更新客户端的最新正文').hitTestable(), findsOneWidget);
      wire.events.add(
        jsonEncode({
          'type': 'announcements',
          'data': noticeSnapshot(
            4,
            '缓存公告',
            discovery: {...remote, 'revision': 1, 'title': '过时发现'},
          ),
        }),
      );
      await tester.pump();
      expect(app.local['discovery']['title'], '即时发现');
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
  testWidgets(
    'home reads old cache and HTTP fallback updates both cards when WebSocket fails',
    (tester) async {
      final remote = {
        ...defaultDiscovery,
        'revision': 1,
        'updated_at': '2026-10-22T09:00:00Z',
        'title': 'HTTP发现',
      };
      final app = AppState(
        serviceApi: HomeService(noticeSnapshot(1, 'HTTP公告', discovery: remote)),
        socketFactory: BrokenHomeConnector.new,
      );
      app.local['announcements'] = noticeSnapshot(0, '旧格式缓存');
      await mountHome(tester, app);
      await tester.pump();
      expect(app.local['announcements']['items'][0]['title'], 'HTTP公告');
      expect(app.local['discovery']['title'], 'HTTP发现');
      expect(find.text('HTTP公告').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
