import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/pages/checkin.dart';

class CloudServiceFixture extends ServiceApi {
  int enrollments = 0, enables = 0, reads = 0;
  bool revoked = false, loseResponse = false, enabled = false;
  Completer<void>? pending;
  @override
  Future<Json> request(
    String path, {
    String? token,
    Json? body,
    String? method,
  }) async {
    if (path.endsWith('/session')) {
      enrollments++;
      await pending?.future;
      revoked = false;
      return {
        'token': 'b' * 64,
        'user_id': 47,
        'expires_at': DateTime.now()
            .add(const Duration(days: 7))
            .toIso8601String(),
      };
    }
    if (revoked) throw ApiFailure(401, 'synthetic-expired-grant');
    if (path.endsWith('/enable')) {
      enables++;
      enabled = true;
      if (loseResponse) throw TimeoutException('synthetic');
    } else if (path.endsWith('/disable')) {
      enabled = false;
    } else {
      reads++;
    }
    return {'enabled': enabled};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SecureVault.setMockInitialValues({}));
  Future<void> storeGrant(AppState app) async {
    await app.site.storage.write(
      key: 'checkin.cloud.47',
      value: jsonEncode({
        'token': 'a' * 64,
        'user_id': 47,
        'expires_at': DateTime.now()
            .add(const Duration(days: 1))
            .toIso8601String(),
      }),
    );
  }

  test('revoked grant is renewed once after explicit enable', () async {
    final service = CloudServiceFixture()..revoked = true;
    final app = AppState(serviceApi: service)..user = {'id': 47};
    await storeGrant(app);
    await app.checkin.setCloud(true);
    expect(service.enrollments, 1);
    expect(service.enables, 1);
    expect(app.checkin.cloud['enabled'], true);
    app.dispose();
  });
  test('lost enable response is reconciled, never repeated', () async {
    final service = CloudServiceFixture()..loseResponse = true;
    final app = AppState(serviceApi: service)..user = {'id': 47};
    await storeGrant(app);
    await app.checkin.setCloud(true);
    expect(service.enables, 1);
    expect(service.reads, 1);
    expect(app.checkin.cloud['enabled'], true);
    app.dispose();
  });
  test(
    'expired status clears local grant and switch; disable never enrolls',
    () async {
      final service = CloudServiceFixture()..revoked = true;
      final app = AppState(serviceApi: service)..user = {'id': 47};
      await storeGrant(app);
      app.checkin.cloud = {'enabled': true};
      await expectLater(app.checkin.refreshCloud(), throwsA(isA<ApiFailure>()));
      expect(app.checkin.cloud, isEmpty);
      expect(await app.site.storage.read(key: 'checkin.cloud.47'), isNull);
      await app.checkin.setCloud(false);
      expect(service.enrollments, 0);
      app.dispose();
    },
  );
  test(
    'account switch during enrollment does not enable or save another UID',
    () async {
      final service = CloudServiceFixture()..pending = Completer<void>();
      final app = AppState(serviceApi: service)..user = {'id': 47};
      final pending = app.checkin.setCloud(true);
      await Future<void>.delayed(Duration.zero);
      app.user = {'id': 9};
      app.generation++;
      service.pending!.complete();
      await expectLater(pending, throwsA(isA<ApiFailure>()));
      expect(service.enables, 0);
      expect(await app.site.storage.read(key: 'checkin.cloud.47'), isNull);
      app.dispose();
    },
  );
  test('cloud errors distinguish server availability from device network', () {
    expect(
      cloudCheckinError(ApiFailure(503, 'synthetic')),
      contains('服务暂时不可用'),
    );
    expect(cloudCheckinError(ApiFailure(401, 'synthetic')), contains('授权已失效'));
    expect(cloudCheckinError(TimeoutException('synthetic')), contains('检查网络'));
  });
}
