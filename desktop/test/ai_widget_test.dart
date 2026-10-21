import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/parser.dart' as html;
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
      expect(find.textContaining('全体共享16段'), findsOneWidget);
      expect(find.text('模型名称'), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester, shot, 'desktop-ai-built-in');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Chinese original bypasses AI and preserves the full text without authentication or quota',
    (tester) async {
      SecureVault.setMockInitialValues({});
      final app = AppState(siteApi: FakeSite(), serviceApi: FakeService())
        ..user = FakeSite.user
        ..starting = false;
      addTearDown(app.dispose);
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      final links = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '作品链接（每行一个，最多3个）',
      );
      await tester.enterText(links, 'https://example.com/work');
      await tester.ensureVisible(find.text('使用粘贴素材'));
      await tester.tap(find.text('使用粘贴素材'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('原文已是中文：跳过AI，原样带入'));
      await tester.tap(find.text('原文已是中文：跳过AI，原样带入'));
      await tester.pumpAndSettle();
      final material = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '补充作品素材（可选）',
      );
      const original = '中文原文。数字123与符号<&>保持原样。';
      await tester.ensureVisible(material);
      await tester.enterText(material, original);
      await tester.tap(find.text('翻译并生成草稿'));
      await tester.pumpAndSettle();
      expect(find.textContaining('没有消耗内置次数'), findsOneWidget);
      expect(find.text('认证仓库账号'), findsNothing);
      expect(app.verified, false);
      final preview = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
      expect(html.parse(preview.html).querySelector('p')!.text, original);
      expect(tester.takeException(), isNull);
      await capture(tester, shot, 'desktop-ai-faithful-original');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
