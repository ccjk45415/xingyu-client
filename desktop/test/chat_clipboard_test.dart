import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/chat.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/pages/conversation.dart';
import 'package:xingyu_desktop/ui/shared.dart';

import 'support/system_test_fonts.dart';

class ClipboardService extends ServiceApi {
  int uploads = 0;
  final jpeg = img.encodeJpg(img.Image(width: 8, height: 8));
  @override
  Future<Uint8List> send(
    String path, {
    String? token,
    Uint8List? body,
    String? method,
    String? type,
    Map<String, String> headers = const {},
  }) async {
    if (body == null) return jpeg;
    expectSync(path, '/media/v1/images?scope=chat&target=1');
    expectSync(type, 'image/jpeg');
    expectSync(img.decodeJpg(body), isNotNull);
    uploads++;
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'image': {'id': 'a' * 32, 'width': 8, 'height': 8},
        }),
      ),
    );
  }
}

class ClipboardChat extends ChatController {
  ClipboardChat(super.app);
  @override
  Future<void> start({bool reconnect = false}) async {
    ready = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadSystemTestFonts);
  setUp(() => SecureVault.setMockInitialValues({}));
  const clipboard = MethodChannel('moe.cangku.xingyu/image_clipboard');
  for (final kind in ['image', 'text', 'account-switch']) {
    testWidgets('chat paste $kind uses existing attachment pipeline', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = ClipboardService();
      final app = AppState(serviceApi: service)
        ..user = {'id': 47}
        ..identity = {'token': 'a' * 64, 'expires_at': '2030-01-01T00:00:00Z'};
      final chat = ClipboardChat(app);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(clipboard, (call) async {
        expectSync(call.method, 'readImage');
        if (kind == 'text') return null;
        if (kind == 'account-switch') {
          app.user = {'id': 48};
          app.generation++;
        }
        return img.encodePng(img.Image(width: 12, height: 12));
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') return {'text': '粘贴文字'};
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(clipboard, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: DeskScope(
            app: app,
            open: (_) {},
            child: Scaffold(body: ChatPage(controller: chat)),
          ),
        ),
      );
      await tester.pump();
      final field = find.byType(TextField);
      await tester.enterText(field, '原文');
      Actions.invoke(
        tester.element(find.byType(EditableText)),
        const PasteTextIntent(SelectionChangedCause.keyboard),
      );
      for (var i = 0; i < 300; i++) {
        await tester.pump();
        if (kind == 'image' && chat.room.image != null) break;
        if (kind == 'text' && chat.room.draft.contains('粘贴文字')) break;
        if (kind == 'account-switch' && app.uid == 48) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      if (kind == 'image') {
        expect(
          service.uploads,
          1,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data)
              .join(' | '),
        );
        expect(chat.room.image?['id'], 'a' * 32);
        expect(chat.room.draft, '原文');
      } else if (kind == 'text') {
        expect(service.uploads, 0);
        expect(chat.room.draft, '原文粘贴文字');
      } else {
        expect(service.uploads, 0);
        expect(chat.room.image, isNull);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      chat.dispose();
      app.dispose();
    });
  }
}
