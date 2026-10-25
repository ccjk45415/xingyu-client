import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/app.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/error_diagnostics.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';

class TimedOutLogin extends SiteApi {
  @override
  Future<Json> login(String account, String password, bool keep) async =>
      throw const SocketException('synthetic timeout with private details');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'caught login socket error enters diagnostics without input data',
    (tester) async {
      SecureVault.setMockInitialValues({});
      await appDiagnostics.clear();
      await tester.binding.setSurfaceSize(const Size(1100, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final app = AppState(siteApi: TimedOutLogin());
      await tester.pumpWidget(MaterialApp(home: LoginPage(app)));
      await tester.enterText(
        find.byKey(const Key('login.account')),
        'synthetic-account',
      );
      await tester.enterText(
        find.byKey(const Key('login.password')),
        'synthetic-password',
      );
      await tester.tap(find.byKey(const Key('login.submit')));
      await tester.pumpAndSettle();
      expect(appDiagnostics.entries.first.source, 'login');
      expect(appDiagnostics.entries.first.type, 'SocketException');
      for (final private in [
        'synthetic-account',
        'synthetic-password',
        'private details',
      ]) {
        expect(appDiagnostics.report(), isNot(contains(private)));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
