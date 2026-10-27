import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/core/checkin_receipts.dart';
import 'package:xingyu_desktop/pages/notification_settings.dart';

class ReceiptService extends ServiceApi {
  final List<Json> values = [];
  final List<String> paths = [];
  @override
  Future<Json> request(
    String path, {
    String? token,
    Json? body,
    String? method,
  }) async {
    paths.add(path);
    expect(token, 'a' * 64);
    if (path.endsWith('/read')) {
      for (final value in values) {
        if ((body!['keys'] as List).contains(value['key'])) {
          value['read'] = true;
        }
      }
      return {'ok': true};
    }
    if (body != null) {
      for (final event in rows(body['events'])) {
        expect(event.keys.toSet(), {'time', 'client', 'method'});
        final value = checkinReceipt(event)!;
        if (!values.any((v) => v['key'] == value['key'])) values.add(value);
      }
    }
    return {'events': values};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppState app(ReceiptService service) => AppState(serviceApi: service)
    ..user = {'id': 47}
    ..identity = {
      'token': 'a' * 64,
      'expires_at': DateTime.now()
          .add(const Duration(days: 1))
          .toIso8601String(),
    };
  Json event({
    String client = 'android',
    String method = 'manual',
    DateTime? time,
  }) => {
    'time': (time ?? DateTime.now()).toUtc().toIso8601String(),
    'client': client,
    'method': method,
  };
  test('success notice names the executing client and method, deduplicates today and routes to checkin', () async {
    final state = app(ReceiptService());
    await state.checkinReceipts.accept(event());
    await state.checkinReceipts.accept(event());
    expect(state.notices.entries, hasLength(1));
    final notice = state.notices.entries.single;
    expect(notice.title, '签到成功');
    expect(notice.preview, 'Android 客户端 · 手动签到');
    expect(noticeRoute(notice).kind, 'checkin');
    expect(state.notices.banner, notice);
    expect(state.notices.unread, 1);
  });
  test('no false success from invalid source, future timestamp or disabled notices', () async {
    final state = app(ReceiptService());
    await state.checkinReceipts.accept(
      event(client: 'cloud', method: 'manual'),
    );
    await state.checkinReceipts.accept(
      event(time: DateTime.now().add(const Duration(hours: 1))),
    );
    expect(state.notices.entries, isEmpty);
    state.local['inAppNoticePrefs'] = {
      '47': {'checkin': false},
    };
    await state.checkinReceipts.accept(event());
    expect(state.notices.entries, isEmpty);
  });
  test('receipts sync without website credentials, preserve read confirmations and do not leak to another uid', () async {
    final service = ReceiptService(), one = app(service);
    await one.checkinReceipts.accept(
      event(client: 'windows', method: 'background'),
    );
    await one.checkinReceipts.sync();
    expect(service.values, hasLength(1));
    final notice = one.notices.entries.single;
    one.notices.readSync.confirm([notice.key], website: false);
    await one.checkinReceipts.syncReads();
    expect(service.values.single['read'], true);
    final two = app(service);
    final events = await two.checkinReceipts.sync();
    for (final e in events) {
      two.notices.acceptCheckin(e);
    }
    expect(two.notices.unread, 0);
    expect(two.notices.banner, isNull);
    two.user = {'id': 48};
    two.generation++;
    expect(two.checkinReceipts.events, isEmpty);
  });
  test('08:00 Beijing is a new notification day; replaying saved receipts does not repeat the banner', () async {
    final before = checkinReceipt(
      event(time: DateTime.parse('2026-10-26T23:59:00Z')),
      now: DateTime.parse('2026-10-27T00:02:00Z'),
    )!;
    final after = checkinReceipt(
      event(time: DateTime.parse('2026-10-27T00:01:00Z')),
      now: DateTime.parse('2026-10-27T00:02:00Z'),
    )!;
    expect(before['key'], isNot(after['key']));
    final first = app(ReceiptService());
    await first.checkinReceipts.accept(event());
    final second = app(ReceiptService())..local = first.local;
    second.notices.acceptCheckin(second.checkinReceipts.events.single);
    expect(second.notices.banner, isNull);
    expect(second.notices.entries, hasLength(1));
  });
}
