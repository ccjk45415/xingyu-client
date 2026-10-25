import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/checkin.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';

import 'checkin_patch_test.dart' show CheckinFixture;

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
}
