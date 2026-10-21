import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/pages/ai_assistant.dart';

import 'widget_test.dart' show FakeSite, FakeService, frames, capture;

void main() {
  setUpAll(() async {
    for (final font in [
      (
        'MaterialIcons',
        'C:/codex-tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ),
      ('Microsoft YaHei UI', 'C:/Windows/Fonts/msyh.ttc'),
    ]) {
      final f = File(font.$2);
      if (await f.exists()) {
        await (FontLoader(font.$1)
              ..addFont(f.readAsBytes().then((b) => ByteData.sublistView(b))))
            .load();
      }
    }
  });
  testWidgets(
    'AI assistant has labeled controls, secure custom settings and scrolls at narrow desktop size',
    (tester) async {
      SecureVault.setMockInitialValues({
        'ai.47': jsonEncode({
          'custom': true,
          'address': 'https://provider.example/v1',
          'key': 'synthetic-fixture-key',
          'model': 'test-model',
        }),
      });
      final app = AppState(siteApi: FakeSite(), serviceApi: FakeService())
        ..user = FakeSite.user
        ..starting = false;
      tester.view.physicalSize = const Size(960, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(app.dispose);
      final shot = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Microsoft YaHei UI'),
          home: RepaintBoundary(
            key: shot,
            child: Scaffold(body: AiAssistantDialog(app)),
          ),
        ),
      );
      await frames(tester);
      await tester.pumpAndSettle();
      expect(find.text('自定义 AI'), findsOneWidget);
      expect(find.text('API Key（可留空，按服务要求）'), findsOneWidget);
      final password = tester
          .widgetList<TextField>(find.byType(TextField))
          .firstWhere((e) => e.obscureText);
      expect(password.controller!.text, 'synthetic-fixture-key');
      expect(password.autocorrect, false);
      await tester.ensureVisible(find.text('保存配置'));
      await tester.tap(find.text('保存配置'));
      await tester.pumpAndSettle();
      expect(
        jsonDecode((await app.site.storage.read(key: 'ai.47'))!)['model'],
        'test-model',
      );
      expect(tester.takeException(), isNull);
      await capture(tester, shot, 'desktop-ai-custom');
      await tester.ensureVisible(find.text('内置 AI'));
      await tester.tap(find.text('内置 AI'));
      await tester.pumpAndSettle();
      expect(find.textContaining('全体共享16次'), findsOneWidget);
      expect(find.text('模型名称'), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester, shot, 'desktop-ai-built-in');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
