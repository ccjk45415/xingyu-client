import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/client_config.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/patch_updates.dart';
import 'package:xingyu_desktop/core/pinned_content.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/pages/checkin.dart';
import 'package:xingyu_desktop/ui/shared.dart';

import 'home_content_test.dart' show mountHome, BrokenHomeConnector;

class CheckinFixture extends SiteApi {
  bool signed = false, fail = false, expired = false;
  int posts = 0;
  Completer<void>? opening;
  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) async {
    expect(path, 'auth/me');
    await opening?.future;
    if (expired) throw ApiFailure(401, 'fixture');
    return {
      'data': {'id': 47, 'nickname': '测试用户', 'is_signed': signed},
    };
  }

  @override
  Future<Json> post(String path, Json body) async {
    expect(path, 'user/signin');
    expect(body, isEmpty);
    posts++;
    if (fail) throw const SocketException('synthetic');
    signed = true;
    return {
      'data': {'point': 2, 'exp': 1, 'continuous_signin': 3},
    };
  }
}

class PatchFixture implements ShorebirdUpdater {
  @override
  bool isAvailable = true;
  bool fail = false, downloaded = false;
  int checks = 0, downloads = 0;
  final tracks = <String>[];
  Completer<void>? waiting;
  @override
  Future<Patch?> readCurrentPatch() async => Patch(number: 1);
  @override
  Future<Patch?> readNextPatch() async => Patch(number: downloaded ? 2 : 1);
  @override
  Future<UpdateStatus> checkForUpdate({UpdateTrack? track}) async {
    checks++;
    tracks.add(track!.name);
    await waiting?.future;
    if (fail) throw const SocketException('synthetic');
    return downloaded ? UpdateStatus.restartRequired : UpdateStatus.outdated;
  }

  @override
  Future<void> update({UpdateTrack? track}) async {
    tracks.add(track!.name);
    downloads++;
    downloaded = true;
  }
}

void main() {
  setUp(() => SecureVault.setMockInitialValues({}));
  test('manual and launch check-in reconcile the server; no repeated POST when already signed', () async {
    final site = CheckinFixture(),
        app = AppState(siteApi: site)..user = {'id': 47};
    await app.checkin.run();
    expect(site.posts, 1);
    expect(app.checkin.signed, true);
    expect(app.checkin.latest['point'], 2);
    await app.checkin.run();
    expect(site.posts, 1);
    app.local['checkinPreferences'] = {
      '47': {'on_open': true},
    };
    await app.checkin.automatic(force: true);
    expect(site.posts, 1);
    app.dispose();
  });
  test('failed POST, expired login and account switch never show a successful check-in', () async {
    final site = CheckinFixture()..fail = true,
        app = AppState(siteApi: site)..user = {'id': 47};
    await expectLater(app.checkin.run(), throwsA(isA<SocketException>()));
    expect(app.checkin.latest, isEmpty);
    expect(app.checkin.signed, false);
    site.expired = true;
    await expectLater(app.checkin.run(), throwsA(isA<ApiFailure>()));
    expect(site.posts, 1);
    site.expired = false;
    site.opening = Completer<void>();
    final pending = app.checkin.run();
    app.user = {'id': 9};
    app.generation++;
    site.opening!.complete();
    await pending;
    expect(site.posts, 1);
    expect(app.uid, 9);
    expect(app.checkin.latest, isEmpty);
    app.dispose();
  });
  test('silent patches use staging, coalesce launch checks and wait for restart; offline is nonfatal', () async {
    final engine = PatchFixture()..waiting = Completer<void>(),
        store = PatchUpdates(updater: engine);
    final first = store.check();
    await store.check();
    engine.waiting!.complete();
    await first;
    expect(engine.checks, 1);
    expect(engine.downloads, 1);
    expect(engine.tracks, everyElement('staging'));
    expect(store.message, contains('下次完全退出'));
    engine.fail = true;
    await store.check(force: true);
    expect(store.message, contains('重试'));
    expect(store.current, 1);
    store.dispose();
  });
  test(
    'signed UI configuration rejects tampering, expiry and arbitrary fields',
    () async {
      final algorithm = Ed25519(),
          pair = await algorithm.newKeyPair(),
          key = base64Encode((await pair.extractPublicKey()).bytes),
          now = DateTime.now().toUtc();
      final doc = {
        'schema': 1,
        'product': 'moe.cangku.xingyu',
        'revision': 1,
        'issued_at': now.toIso8601String(),
        'expires_at': now.add(const Duration(days: 1)).toIso8601String(),
        'config': defaultClientUi,
      };
      Future<Json> sign(Json value) async {
        final bytes = utf8.encode(jsonEncode(value));
        return {
          'payload': base64Encode(bytes),
          'signature': base64Encode(
            (await algorithm.sign(bytes, keyPair: pair)).bytes,
          ),
        };
      }

      final envelope = await sign(doc);
      expect(await verifyClientConfig(envelope, publicKey: key), isNotNull);
      expect(
        await verifyClientConfig({
          ...envelope,
          'payload': base64Encode(
            utf8.encode(jsonEncode({...doc, 'revision': 999})),
          ),
        }, publicKey: key),
        isNull,
      );
      expect(
        await verifyClientConfig(
          envelope,
          publicKey: key,
          now: now.add(const Duration(days: 2)),
        ),
        isNull,
      );
      expect(
        await verifyClientConfig(
          await sign({
            ...doc,
            'config': {...defaultClientUi, 'script': 'bad'},
          }),
          publicKey: key,
        ),
        isNull,
      );
    },
  );
  test(
    'pinned items lead while preserving server order and deduplicating IDs',
    () {
      expect(
        pinnedFirst([
          {'id': 1},
          {'id': 2, 'is_sticky': true},
          {'id': 3, 'is_sticky': 1},
          {'id': 2},
        ]).map((p) => p['id']),
        [2, 3, 1],
      );
    },
  );
  for (final width in [360.0, 430.0, 1280.0]) {
    testWidgets('compact banner and check-in card fit width $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      final app = AppState(socketFactory: BrokenHomeConnector.new)
        ..user = {'id': 47, 'nickname': '测试用户'};
      await mountHome(tester, app);
      expect(
        tester.getSize(find.byKey(const Key('home.compact-banner'))).height,
        lessThan(160),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: DeskScope(
            app: app,
            open: (_) {},
            child: const Scaffold(body: CheckinCard()),
          ),
        ),
      );
      expect(find.widgetWithText(TextButton, '签到'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      await tester.binding.setSurfaceSize(null);
    });
  }
}
