import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/system_notices.dart';

import 'in_app_notices_test.dart'
    show NoticeSite, NoticeService, makeApp, conversation;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  bool allowed = true;
  Json open = {};
  setUp(() {
    calls.clear();
    allowed = true;
    open = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemNotices.channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'request' => allowed,
            'status' => {'supported': true, 'granted': allowed},
            'takeOpen' => open,
            _ => null,
          };
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemNotices.channel, null);
  });
  test('permission denial does not enable notifications; privacy defaults to hidden', () async {
    final app = makeApp(NoticeSite(), NoticeService());
    allowed = false;
    await expectLater(
      app.notices.setPreference('system', true),
      throwsA(isA<ApiFailure>()),
    );
    expect(app.notices.systemEnabled, false);
    allowed = true;
    await app.notices.setPreference('system', true);
    expect(app.notices.systemEnabled, true);
    final config =
        calls.lastWhere((c) => c.method == 'configure').arguments as Map;
    expect(config['uid'], 47);
    expect(config['preferences']['preview'], isNot(true));
    expect(jsonEncode(config), isNot(contains('synthetic-only')));
    app.dispose();
  });
  test('background desktop receives system reminders once, without a foreground banner or preview', () async {
    final site = NoticeSite(), service = NoticeService();
    final current = makeApp(site, service);
    service.conversations = [conversation(1)];
    await current.notices.refresh();
    await current.notices.setPreference('system', true);
    current.notices.route = 'dm';
    current.notices.routeId = 77;
    current.notices.pause();
    service.conversations = [conversation(2)];
    await current.notices.refresh();
    await Future<void>.delayed(Duration.zero);
    final shown = calls.where((c) => c.method == 'show').toList();
    expect(shown.length, 1);
    expect(shown.single.arguments['body'], '你有一条新的消息，点击查看');
    expect(current.notices.banner, null);
    expect(current.notices.unread, 1);
    await current.notices.refresh();
    expect(calls.where((c) => c.method == 'show').length, 1);
    await current.notices.stopSystem();
    expect(calls.last.arguments['enabled'], false);
    current.dispose();
  });
  test('a notification for another account cannot open its route', () async {
    final app = makeApp(NoticeSite(), NoticeService());
    open = {'uid': 99, 'key': 'dm:1', 'kind': 'dm', 'target': 123};
    await app.notices.syncSystem();
    expect(app.notices.opened, null);
    open = {'uid': 47, 'key': 'dm:2', 'kind': 'dm', 'target': 77};
    await app.notices.syncSystem();
    expect(app.notices.opened?.target, 77);
    app.dispose();
  });
}
