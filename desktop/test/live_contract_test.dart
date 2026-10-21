import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/native_storage.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  final account = Platform.environment['XINGYU_TEST_ACCOUNT'],
      password = Platform.environment['XINGYU_TEST_PASSWORD'];
  testWidgets(
    'authorized read-only website and certified production WSS contract',
    (tester) async {
      SecureVault.setMockInitialValues({});
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          final site = SiteApi(), service = ServiceApi();
          String? token;
          try {
            final user = await site.login(account!, password!, false),
                uid = number(user['id']);
            expect(uid > 0, isTrue);
            final authors = rows(
              (await site.get('user/list', {
                'search': text(user['nickname']),
                'page': 1,
                'per_page': 20,
              }))['data'],
            );
            expect(
              authors.any((a) => number(a['id']) == uid),
              isTrue,
              reason: 'author search returns own matching nickname',
            );
            expect(
              authors.every(
                (a) => a.containsKey('nickname') && a.containsKey('avatar'),
              ),
              isTrue,
            );
            expect(
              number(object((await site.get('auth/me'))['data'])['id']) == uid,
              isTrue,
            );
            expect(
              rows(
                (await site.get('category/list', {
                  'all': 1,
                  'type': 'post',
                }))['data'],
              ).isNotEmpty,
              isTrue,
            );
            final list = await site.get('post/list', {
                  'page': 1,
                  'per_page': 1,
                  'simple': 1,
                  'include': 'user,categories:simple',
                }),
                posts = rows(list['data']);
            expect(posts.isNotEmpty, isTrue);
            final post = object(
              (await site.get('post/info', {
                'id': posts.first['id'],
                'include': 'user,tags,categories,favorited,upvoted',
                'exclude_view': 1,
              }))['data'],
            );
            expect(number(post['id']) > 0, isTrue);
            for (final query in [
              (
                'comment/list',
                <String, dynamic>{
                  'post_id': post['id'],
                  'parent_id': 0,
                  'page': 1,
                  'per_page': 1,
                  'include': 'user,children.user',
                },
              ),
              (
                'user/favoritePost',
                <String, dynamic>{
                  'id': uid,
                  'page': 1,
                  'per_page': 1,
                  'simple': 1,
                },
              ),
              (
                'user/comment',
                <String, dynamic>{
                  'id': uid,
                  'page': 1,
                  'per_page': 1,
                  'include': 'post:simple,user',
                },
              ),
              (
                'user/notification',
                <String, dynamic>{
                  'action': 'reply',
                  'page': 1,
                  'per_page': 1,
                  'include': 'user,causer,subject',
                },
              ),
              ('user/creditLog', <String, dynamic>{'page': 1, 'per_page': 1}),
              (
                'post/list',
                <String, dynamic>{
                  'user_id': uid,
                  'status': 'draft',
                  'page': 1,
                  'per_page': 1,
                  'include': 'categories:simple,meta:include(reject_reason)',
                },
              ),
            ]) {
              expect(
                (await site.get(query.$1, query.$2))['code'] == 0,
                isTrue,
                reason: query.$1,
              );
            }
            expect((await service.request('/health'))['protocol'], 3);
            final session = await service.request(
              '/dm/v1/session',
              body: {'site_cookie': site.cookieHeader, 'expected_user_id': uid},
            );
            token = text(session['token']);
            expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(token), isTrue);
            expect(number(object(session['user'])['id']) == uid, isTrue);
            expect(
              number(
                    object(
                      (await service.request('/v1/me', token: token))['user'],
                    )['id'],
                  ) ==
                  uid,
              isTrue,
            );
            for (final channel in ['1', '2']) {
              final ws = await WebSocket.connect(
                '${serviceOrigin.replaceFirst('https:', 'wss:')}/ws?channel=$channel',
                headers: {'Authorization': 'Bearer $token'},
              ).timeout(const Duration(seconds: 20));
              try {
                final events = ws.asBroadcastStream();
                final raw = await events.first.timeout(
                  const Duration(seconds: 20),
                );
                final ready = object(jsonDecode(raw as String));
                expect(ready['type'], 'ready');
                expect(ready['channel'], channel);
                expect(number(object(ready['user'])['id']) == uid, isTrue);
                final heartbeat = events
                    .firstWhere((v) => v == 'pong')
                    .timeout(const Duration(seconds: 20));
                ws.add('ping');
                expect(await heartbeat, 'pong');
              } finally {
                await ws.close();
              }
            }
          } finally {
            if (token != null) {
              await service.request('/dm/v1/logout', token: token, body: {});
            }
            site.close();
            service.close();
          }
        }, _RealHttp()),
      );
    },
    skip: account == null || password == null,
  );
}
