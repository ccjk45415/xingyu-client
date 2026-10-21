import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/chat.dart';
import 'package:xingyu_desktop/core/media.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';

class _RealHttp extends HttpOverrides {}

class _SyntheticSite extends SiteApi {
  final int owner;
  _SyntheticSite(this.owner);
  Json get user => {
    'id': owner,
    'nickname': '仓库用户$owner',
    'avatar': 'https://images.example/$owner.jpg',
  };
  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) async => {
    'code': 0,
    'data': user,
  };
}

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 180; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
  throw StateError('Expected local transport event did not arrive');
}

void main() {
  final origin = Platform.environment['CHAT_TEST_ORIGIN'],
      root = Platform.environment['CHAT_TEST_ROOT'];
  testWidgets(
    'actual Dart chat lifecycle, channel isolation, mentions/replies and authenticated image/DM wire',
    (tester) async {
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          SecureVault.setMockInitialValues({});
          AppState make(int id, String token) {
            final site = _SyntheticSite(id);
            return AppState(
                siteApi: site,
                serviceApi: ServiceApi(origin: origin),
              )
              ..starting = false
              ..user = site.user
              ..identity = {
                'token': token,
                'user': site.user,
                'expires_at': DateTime.now()
                    .add(const Duration(days: 6))
                    .toUtc()
                    .toIso8601String(),
              };
          }

          final a = make(1001, Platform.environment['CHAT_TEST_A']!),
              b = make(1002, Platform.environment['CHAT_TEST_B']!),
              ca = ChatController(a),
              cb = ChatController(b);
          try {
            await ca.start();
            await cb.start();
            await until(() => ca.ready && cb.ready);
            ca.room.draft = 'Flutter桌面认证消息';
            ca.send();
            await until(() => ca.room.pending == null);
            final original = ca.room.messages.values.firstWhere(
              (m) => m['text'] == 'Flutter桌面认证消息',
            );
            expect(number(object(original['sender'])['id']), 1001);
            expect(ca.room.draft, isEmpty);
            cb.room.reply = original;
            cb.room.mentions[1001] = '@仓库用户1001(UID:1001)';
            cb.room.draft = '@仓库用户1001(UID:1001) 桌面引用回复';
            cb.send();
            await until(() => cb.room.pending == null);
            final reply = cb.room.messages.values.firstWhere(
              (m) => m['text'] == '@仓库用户1001(UID:1001) 桌面引用回复',
            );
            expect(
              number(object(reply['reply_to'])['id']),
              number(original['id']),
            );
            expect(rows(reply['mentions']).single['id'], 1001);
            expect(cb.room.mentions, isEmpty);
            await cb.choose('2');
            await until(() => cb.ready);
            expect(
              cb.room.messages.containsKey(number(original['id'])),
              isFalse,
            );
            await cb.choose('1');
            await until(() => cb.ready);
            final photo = await File(
              '$root/cloudflare-chat/test/fixtures/chat-test.jpg',
            ).readAsBytes();
            ca.room.image = await uploadChatImage(a, photo, 'chat', '1');
            final publicId = text(ca.room.image!['id']);
            await Future<void>.delayed(const Duration(milliseconds: 3100));
            ca.send();
            await until(() => ca.room.pending == null);
            await until(
              () => cb.room.messages.values.any(
                (m) => object(m['image'])['id'] == publicId,
              ),
            );
            expect(await MediaCache.get(b, publicId), photo);
            final private = await uploadChatImage(a, photo, 'dm', '1002'),
                nonceId = nonce(),
                payload = {
                  'peer_id': 1002,
                  'text': '本机Dart私信图片联调',
                  'image_id': private['id'],
                  'client_id': nonceId,
                };
            final sent = await a.service.request(
                  '/dm/v1/messages',
                  token: a.token,
                  body: payload,
                ),
                retry = await a.service.request(
                  '/dm/v1/messages',
                  token: a.token,
                  body: payload,
                );
            expect(
              object(sent['message'])['id'],
              object(retry['message'])['id'],
            );
            expect(await MediaCache.get(b, text(private['id'])), photo);
            await Future.wait([cb.choose('2'), cb.choose('1')]);
            await until(() => cb.ready && cb.channel == '1');
            expect(
              cb.rooms['2']!.messages.values.every((m) => m['channel'] == '2'),
              isTrue,
            );
            ca.pause();
            expect(ca.active, isFalse);
            expect(
              ca.room.messages.containsKey(number(original['id'])),
              isTrue,
            );
            await ca.start();
            await until(() => ca.ready);
            await File('$root/evidence/desktop-transport.json').writeAsString(
              jsonEncode({
                'local_only': true,
                'runtime': 'Pages -> internal binding -> workerd/DO',
                'client': 'actual Dart ChatController + ServiceApi',
                'channel_isolation': 'pass',
                'mentions_and_replies': 'pass',
                'media_chat_and_private': 'pass',
                'idempotent_private_send': 'pass',
                'pause_resume_and_stale_generations': 'pass',
                'production_messages_sent': 0,
                'real_website_requests': 0,
              }),
            );
          } finally {
            ca.dispose();
            cb.dispose();
            a.dispose();
            b.dispose();
            MediaCache.clear();
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }, _RealHttp()),
      );
    },
    skip: origin == null || root == null,
  );
}
