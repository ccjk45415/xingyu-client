import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/updates.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/ui/shared.dart';

import 'widget_test.dart' show FakeSite, FakeService;

class UpdateService extends FakeService {
  int code = 999;
  bool invalid = false;
  @override
  Future<Json> request(
    String path, {
    String? token,
    Json? body,
    String? method,
  }) async => {
    'available': true,
    'platform': 'windows-x64',
    'versionName': '9.9.9',
    'versionCode': code,
    'notes': '新增通知与更新提醒',
    'size': 123,
    'sha256': 'a' * 64,
    'url': invalid
        ? 'https://invalid.example/update.zip'
        : '$serviceOrigin/releases/update.zip',
  };
}

void main() {
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets(
    'startup offers each new release once; decline makes no installation and next version can prompt',
    (tester) async {
      final service = UpdateService(),
          app = AppState(siteApi: FakeSite(), serviceApi: UpdateService());
      app.dispose();
      final current = AppState(siteApi: FakeSite(), serviceApi: service);
      late BuildContext anchor;
      await tester.pumpWidget(
        MaterialApp(
          home: DeskScope(
            app: current,
            open: (_) {},
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  anchor = context;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      final first = offerStartupUpdate(anchor);
      await tester.pumpAndSettle();
      expect(find.text('立即更新'), findsOneWidget);
      await tester.tap(find.text('暂时不更新'));
      await tester.pumpAndSettle();
      await first;
      expect(current.local['updateOffers'], ['windows-x64:999']);
      await offerStartupUpdate(anchor);
      await tester.pumpAndSettle();
      expect(find.text('立即更新'), findsNothing);
      service.code = 1000;
      final next = offerStartupUpdate(anchor);
      await tester.pumpAndSettle();
      expect(find.text('立即更新'), findsOneWidget);
      await tester.tap(find.text('暂时不更新'));
      await tester.pumpAndSettle();
      await next;
      service.code = 1001;
      service.invalid = true;
      await expectLater(offerStartupUpdate(anchor), throwsA(isA<ApiFailure>()));
      expect(
        current.local['updateOffers'],
        isNot(contains('windows-x64:1001')),
      );
      await tester.pumpWidget(const SizedBox());
      current.dispose();
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
