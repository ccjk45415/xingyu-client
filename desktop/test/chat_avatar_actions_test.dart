import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/app.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/pages/conversation.dart';
import 'package:xingyu_desktop/pages/reading.dart';
import 'package:xingyu_desktop/ui/shared.dart';

import 'widget_test.dart' show FakeSite, FakeService, OfflineSocket, frames;

void main() {
  setUpAll(() async {
    for (final (family, path) in [
      ('Microsoft YaHei UI', 'C:/Windows/Fonts/msyh.ttc'),
      (
        'MaterialIcons',
        'C:/codex-tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ),
    ]) {
      await (FontLoader(family)..addFont(
            File(path)
                .readAsBytes()
                .then((bytes) => ByteData.sublistView(bytes)),
          ))
          .load();
    }
  });
  setUp(() => SecureVault.setMockInitialValues({}));
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'avatar tap opens author; hold mentions without navigating at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app =
            AppState(
                siteApi: FakeSite(),
                serviceApi: FakeService(),
                socketFactory: OfflineSocket.new,
              )
              ..starting = false
              ..user = {...FakeSite.user}
              ..identity = {
                'token': 'synthetic-only',
                'expires_at': '2030-01-01T00:00:00Z',
              };
        await tester.pumpWidget(XingyuApp(app: app));
        await frames(tester);
        void open(DeskRoute route) =>
            tester.widget<DeskScope>(find.byType(DeskScope).first).open(route);
        open(const DeskRoute('chat', '聊天室'));
        await frames(tester);
        final chat = tester.widget<ChatPage>(find.byType(ChatPage)).controller!;
        chat.pause();
        chat.ready = true;
        chat.room.historyLoaded = true;
        chat.room.messages[1] = {
          'id': 1,
          'channel': '1',
          'sender': {'id': 77, 'nickname': '测试同好'},
          'text': '头像操作测试',
          'created_at': '2026-10-24T12:00:00Z',
        };
        chat.room.draft = '保留的草稿 ';
        chat.update();
        await frames(tester);
        final avatar = find.byKey(const ValueKey('chat-avatar:1'));
        await tester.longPress(avatar);
        await frames(tester);
        expect(find.byType(AuthorPage), findsNothing);
        expect(chat.room.draft, '保留的草稿 @测试同好(UID:77) ');
        expect(chat.room.mentions.keys, contains(77));
        final before = chat.room.draft;
        await tester.tap(avatar);
        await frames(tester);
        expect(find.byType(AuthorPage), findsOneWidget);
        expect(tester.widget<AuthorPage>(find.byType(AuthorPage)).id, 77);
        expect(chat.room.draft, before);
        open(const DeskRoute('chat', '聊天室'));
        await frames(tester);
        expect(chat.room.draft, before);
        expect(find.byKey(const ValueKey('chat-avatar:1')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        app.dispose();
        await tester.pump(const Duration(seconds: 21));
      },
    );
  }
  testWidgets('private-message avatar retains its existing author action', (
    tester,
  ) async {
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            messageData: const {'id': 9, 'text': '私信'},
            user: const {'id': 77, 'nickname': '同好'},
            mine: true,
            onName: () => opens++,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('chat-avatar:9')));
    expect(opens, 1);
  });
}
