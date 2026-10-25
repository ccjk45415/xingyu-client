import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/native_storage.dart';

import 'in_app_notices_test.dart'
    show NoticeSite, NoticeService, makeApp, chatMessage, replyMessage;

class SharedNoticeSite extends NoticeSite {
  int acknowledgements = 0;
  @override
  Future<Json> post(String path, Json body) async {
    if (path == 'user/makeNotificationAsRead') {
      acknowledgements++;
      for (final row in [...replies, ...votes]) {
        if ((body['ids'] as List).contains(row['id'])) {
          row['read_at'] = '2026-10-25T00:00:00Z';
        }
      }
      return {'code': 0};
    }
    return super.post(path, body);
  }
}

class SharedNoticeService extends NoticeService {
  final Set<String> confirmed = {};
  bool offline = false;
  Completer<void>? writing;
  @override
  Future<Json> request(
    String path, {
    String? token,
    Json? body,
    String? method,
  }) async {
    if (path == '/dm/v1/notice-reads') {
      if (offline) throw const SocketException('synthetic');
      if (body != null) {
        await writing?.future;
        confirmed.addAll((body['keys'] as List).cast<String>());
        return {'ok': true};
      }
      return {'keys': confirmed.toList()};
    }
    return super.request(path, token: token, body: body, method: method);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SecureVault.setMockInitialValues({}));
  test('one client confirms a mention and reply; other client clears badge/banner without acknowledging a fetch', () async {
    final site = SharedNoticeSite(),
        service = SharedNoticeService(),
        a = makeApp(site, service),
        b = makeApp(site, service);
    await a.notices.refresh();
    await b.notices.refresh();
    site.replies = [replyMessage('reply-one')];
    service.messages['1'] = [chatMessage(17)];
    await a.notices.refresh();
    await b.notices.refresh();
    expect(a.notices.unread, 2);
    expect(b.notices.unread, 2);
    expect(service.confirmed, isEmpty);
    a.notices.read(
      a.notices.entries.firstWhere((n) => n.kind == 'chatMention'),
    );
    await a.notices.readSync.sync();
    await b.notices.refresh();
    expect(b.notices.unread, 1);
    a.notices.read(a.notices.entries.firstWhere((n) => n.kind == 'postReply'));
    await a.notices.readSync.sync();
    await b.notices.refresh();
    expect(b.notices.unread, 0);
    expect(b.notices.banner, isNull);
    expect(site.acknowledgements, 1);
    expect(jsonEncode(a.local), isNot(contains('私密')));
    a.dispose();
    b.dispose();
  });
  test(
    'opening notification list alone does not mark new notifications read',
    () async {
      final site = SharedNoticeSite(),
          service = SharedNoticeService(),
          a = makeApp(site, service);
      await a.notices.refresh();
      a.notices.route = 'noticeCenter';
      site.replies = [replyMessage('unread')];
      await a.notices.refresh();
      expect(a.notices.unread, 1);
      expect(service.confirmed, isEmpty);
      a.dispose();
    },
  );
  test('offline confirmation remains queued and is retried; late responses cannot alter another account', () async {
    final site = SharedNoticeSite(),
        service = SharedNoticeService(),
        a = makeApp(site, service);
    service.offline = true;
    a.notices.readSync.confirm(['chat:1:99']);
    await expectLater(
      a.notices.readSync.sync(),
      throwsA(isA<SocketException>()),
    );
    expect(object(object(a.local['noticeReadSync'])['47'])['pending'], [
      'chat:1:99',
    ]);
    service.offline = false;
    await a.notices.readSync.sync();
    expect(service.confirmed, contains('chat:1:99'));
    expect(object(object(a.local['noticeReadSync'])['47'])['pending'], isEmpty);
    service.writing = Completer<void>();
    a.notices.readSync.confirm(['chat:2:100']);
    final pending = a.notices.readSync.sync();
    await Future<void>.delayed(Duration.zero);
    a.user = {'id': 99};
    a.generation++;
    a.identity = null;
    service.writing!.complete();
    await expectLater(pending, throwsA(isA<ApiFailure>()));
    expect(object(a.local['noticeReadSync']).containsKey('99'), false);
    a.dispose();
  });
}
