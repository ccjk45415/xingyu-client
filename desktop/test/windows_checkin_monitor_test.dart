import 'dart:async';

import 'package:xingyu_desktop/core/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/checkin.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';

import 'checkin_patch_test.dart' show CheckinFixture;

class TemporaryAccessFixture extends CheckinFixture {
  int? status;
  int reads = 0;
  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) async {
    reads++;
    if (status != null) throw ApiFailure(status!, 'synthetic access failure');
    return super.get(path, params);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SecureVault.setMockInitialValues({}));
  testWidgets(
    'login during final minute signs immediately; cached signed flag cannot hide server reset',
    (tester) async {
      final site = CheckinFixture(),
          app = AppState(siteApi: site)..user = {'id': 47, 'is_signed': true};
      app.local['checkinPreferences'] = {
        '47': {'background': true},
      };
      final monitor = CheckinController(
        app,
        windows: true,
        now: () => DateTime.utc(2026, 10, 25, 15, 59),
      );
      await monitor.automatic(
        force: true,
        freshUser: {'id': 47, 'is_signed': false},
      );
      expect(site.posts, 1);
      expect(monitor.signed, true);
      site.signed = false;
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(site.posts, 2);
      await monitor.automatic(force: true);
      expect(site.posts, 2);
      monitor.dispose();
      app.dispose();
    },
  );
  testWidgets(
    'background option works in tray without persisted login; disabling stops polls',
    (tester) async {
      final site = CheckinFixture(),
          app = AppState(siteApi: site)..user = {'id': 47};
      final monitor = CheckinController(app, windows: true);
      monitor.setWindowVisible(false);
      await monitor.setPreference('background', true);
      await tester.pump();
      expect(site.posts, 1);
      expect(site.remember, false);
      site.signed = false;
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(site.posts, 2);
      await monitor.setPreference('background', false);
      site.signed = false;
      await tester.pump(const Duration(minutes: 2));
      expect(site.posts, 2);
      monitor.dispose();
      app.dispose();
    },
  );
  testWidgets('expired login suspends polling until a new account generation', (
    tester,
  ) async {
    final site = CheckinFixture()..expired = true,
        app = AppState(siteApi: site)..user = {'id': 47};
    app.local['checkinPreferences'] = {
      '47': {'background': true},
    };
    final monitor = CheckinController(app, windows: true);
    await monitor.automatic(force: true);
    expect(monitor.message, contains('登录已失效'));
    site.expired = false;
    await tester.pump(const Duration(minutes: 2));
    expect(site.posts, 0);
    app.generation++;
    await monitor.automatic(force: true);
    expect(site.posts, 1);
    monitor.dispose();
    app.dispose();
  });
  for (final status in [403, 419, 302, 503]) {
    testWidgets(
      'temporary HTTP $status retries from tray without relogin or toggling',
      (tester) async {
        final site = TemporaryAccessFixture()..status = status;
        final app = AppState(siteApi: site)..user = {'id': 47};
        app.local['checkinPreferences'] = {
          '47': {'background': true},
        };
        var proxyRefreshes = 0;
        final monitor = CheckinController(
          app,
          windows: true,
          refreshProxy: () async {
            proxyRefreshes++;
          },
        )..setWindowVisible(false);
        await monitor.automatic(force: true);
        expect(monitor.message, contains('自动重试'));
        expect(site.posts, 0);
        site.status = null;
        await tester.pump(const Duration(seconds: 15));
        await tester.pump();
        expect(site.posts, 1);
        expect(proxyRefreshes, 2);
        expect(monitor.latest['source'], 'background');
        site.signed = false;
        await tester.pump(const Duration(seconds: 30));
        await tester.pump();
        expect(site.posts, 2);
        monitor.dispose();
        app.dispose();
      },
    );
  }
  testWidgets(
    'manual successful check-in resumes a monitor paused by expired login',
    (tester) async {
      final site = CheckinFixture()..expired = true;
      final app = AppState(siteApi: site)..user = {'id': 47};
      app.local['checkinPreferences'] = {
        '47': {'background': true},
      };
      final monitor = CheckinController(
        app,
        windows: true,
        refreshProxy: () async {},
      )..setWindowVisible(false);
      await monitor.automatic(force: true);
      expect(monitor.message, contains('登录已失效'));
      site.expired = false;
      await monitor.run();
      expect(site.posts, 1);
      site.signed = false;
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(site.posts, 2);
      monitor.dispose();
      app.dispose();
    },
  );
  testWidgets(
    'disabling while a proxy refresh is pending never submits check-in',
    (tester) async {
      final site = CheckinFixture();
      final app = AppState(siteApi: site)..user = {'id': 47};
      app.local['checkinPreferences'] = {
        '47': {'background': true},
      };
      final proxy = Completer<void>();
      final monitor = CheckinController(
        app,
        windows: true,
        refreshProxy: () => proxy.future,
      )..setWindowVisible(false);
      final pending = monitor.automatic(force: true);
      await monitor.setPreference('background', false);
      proxy.complete();
      await pending;
      await tester.pump();
      expect(site.posts, 0);
      expect((app.site as CheckinFixture).posts, 0);
      monitor.dispose();
      app.dispose();
    },
  );
  test(
    'Android background success status is checked against the Shanghai date',
    () {
      var now = DateTime.utc(2026, 10, 25, 15, 59);
      final app = AppState(siteApi: CheckinFixture())..user = {'id': 47};
      final monitor = CheckinController(app, windows: false, now: () => now);
      monitor.background = {'status': '今日已签到', 'time': '2026-10-25T00:00:00Z'};
      expect(monitor.backgroundStatus, '今日已签到');
      now = DateTime.utc(2026, 10, 25, 16, 0);
      expect(monitor.backgroundStatus, contains('今日待确认'));
      monitor.background = {'status': '今日已签到', 'time': 'bad'};
      expect(monitor.backgroundStatus, contains('时间未知'));
      monitor.background = {'status': '网络暂不可用，等待下次尝试'};
      expect(monitor.backgroundStatus, '网络暂不可用，等待下次尝试');
      monitor.dispose();
      app.dispose();
    },
  );
}
