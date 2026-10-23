import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xingyu_desktop/app.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/platform.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/pages/ai_assistant.dart';
import 'package:xingyu_desktop/ui/shared.dart';

class LocalSite extends SiteApi {
  static final user = <String, dynamic>{
    'id': 47,
    'nickname': '手机布局测试',
    'avatar': '',
    'permissions': [],
  };
  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) async => {
    'data': path == 'category/list'
        ? [
            {'id': 12, 'name': '测试分类', 'children': []},
          ]
        : [],
    'meta': {
      'pagination': {'total_pages': 1},
    },
  };
  @override
  Future<Json> post(String path, Json body) async =>
      throw StateError('Smoke test must never submit');
}

class LocalService extends ServiceApi {
  @override
  Future<Json> request(
    String path, {
    String? token,
    Json? body,
    String? method,
  }) async {
    if (body != null) throw StateError('Smoke test must never write online');
    return {
      'ids': [],
      'authors': [],
      'following_count': 0,
      'follower_count': 0,
      'conversations': [],
    };
  }
}

class Offline extends SocketConnector {
  @override
  Future<WebSocket> connect(
    String url, {
    Map<String, dynamic>? headers,
  }) async => throw const SocketException('offline test');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android native vault, proxy, mobile navigation, authoring and AI panel',
    (tester) async {
      expect(Platform.isAndroid, true);
      await initializePlatform();
      const vault = SecureVault();
      final key = 'smoke.${nonce()}';
      try {
        await vault.write(key: key, value: '测试 Flutter · 安全存储 ✦');
        expect(await vault.read(key: key), '测试 Flutter · 安全存储 ✦');
        await vault.write(key: key, value: 'second');
        expect(await vault.read(key: key), 'second');
        await vault.delete(key: key);
        expect(await vault.read(key: key), null);
      } finally {
        await vault.delete(key: key);
      }

      final app =
          AppState(
              siteApi: LocalSite(),
              serviceApi: LocalService(),
              socketFactory: Offline.new,
            )
            ..starting = false
            ..user = LocalSite.user
            ..categories = [
              {'id': 12, 'name': '测试分类'},
            ]
            ..identity = {
              'token': 'synthetic-device-test',
              'expires_at': '2030-01-01T00:00:00Z',
            };
      await tester.pumpWidget(XingyuApp(app: app));
      await tester.pumpAndSettle();
      for (final kind in [
        'categories',
        'rank',
        'chat',
        'followingFeed',
        'mine',
      ]) {
        await tester.tap(find.byKey(ValueKey('mobile.nav.$kind')));
        await tester.pump(const Duration(milliseconds: 500));
        if (kind == 'chat') {
          await tester.tap(find.text('频道二'));
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(tester.takeException(), null, reason: kind);
      }
      tester
          .widget<DeskScope>(find.byType(DeskScope).first)
          .open(const DeskRoute('editor', '新建投稿'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('AI 投稿助手').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('AI 投稿助手').first);
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistantDialog), findsOneWidget);
      await tester.tap(find.byTooltip('关闭助手'));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('editor.content'));
      await tester.ensureVisible(field);
      await tester.enterText(
        field,
        List.generate(100, (i) => '第$i行，手机正常模式编辑与滑动测试。').join('\n'),
      );
      await tester.pumpAndSettle();
      final inner = tester.state<ScrollableState>(
        find.descendant(of: field, matching: find.byType(Scrollable)).first,
      );
      expect(inner.position.maxScrollExtent, greaterThan(0));
      inner.position.jumpTo(0);
      await tester.pump();
      inner.position.jumpTo(inner.position.maxScrollExtent);
      await tester.pump();
      expect(inner.position.pixels, greaterThan(0));
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      debugPrint(
        'XINGYU_ANDROID_SMOKE_PASS: vault, proxy, 6-tabs, channels, normal-editor, long-scroll, ai-panel; real website writes=0',
      );
    },
  );
}
