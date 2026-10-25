import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/core/visual_editor.dart';
import 'package:xingyu_desktop/core/editor_extra_rules.dart';
import 'package:xingyu_desktop/pages/authoring.dart';
import 'package:xingyu_desktop/ui/shared.dart';

import 'widget_test.dart'
    show FakeSite, FakeService, OfflineSocket, frames, capture;

void main() {
  final captureKey = GlobalKey();
  setUpAll(() async {
    final flutterRoot =
        Platform.environment['FLUTTER_ROOT'] ?? 'C:/codex-tools/flutter';
    await (FontLoader('MaterialIcons')..addFont(
          File(
            '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        ))
        .load();
    final file = File('C:/Windows/Fonts/msyh.ttc');
    if (await file.exists()) {
      await (FontLoader(
        'Microsoft YaHei UI',
      )..addFont(file.readAsBytes().then(ByteData.sublistView))).load();
    }
  });
  Future<AppState> mount(WidgetTester tester, {bool mobile = false}) async {
    SecureVault.setMockInitialValues({});
    final app =
        AppState(
            siteApi: FakeSite(),
            serviceApi: FakeService(),
            socketFactory: OfflineSocket.new,
          )
          ..starting = false
          ..user = Map.from(FakeSite.user);
    tester.view.physicalSize = mobile
        ? const Size(390, 844)
        : const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          theme: ThemeData(
            fontFamily: 'Microsoft YaHei UI',
            platform: mobile ? TargetPlatform.android : TargetPlatform.windows,
          ),
          home: DeskScope(
            app: app,
            open: (_) {},
            child: const Scaffold(
              body: PostEditor(DeskRoute('editor', '新建投稿')),
            ),
          ),
        ),
      ),
    );
    await frames(tester);
    return app;
  }

  Future<void> close(WidgetTester tester, AppState app) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
    app.dispose();
  }

  Future<VisualHtmlController> selectLink(WidgetTester tester) async {
    final field = find.byKey(const Key('editor.content'));
    final controller =
        tester.widget<TextField>(field).controller! as VisualHtmlController;
    controller.value = controller.value.copyWith(text: '前原始链接后');
    controller.load(
      '<p>前<a href="https://example.com/a" target="_blank"><strong>原始链接</strong></a>后</p>',
    );
    controller.onSourceChanged?.call();
    final at = controller.text.indexOf('始链');
    controller.selection = TextSelection(baseOffset: at, extentOffset: at + 2);
    await tester.ensureVisible(field);
    await tester.tap(field);
    controller.selection = TextSelection(baseOffset: at, extentOffset: at + 2);
    await tester.pump();
    final editable = tester.state<EditableTextState>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    editable.showToolbar();
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets(
    'partial link selection unlinks whole anchor and can undo; groups retain selection',
    (tester) async {
      final app = await mount(tester);
      final editor = await selectLink(tester);
      expect(find.byKey(const Key('editor.context.menu')), findsOneWidget);
      expect(find.text('修改链接'), findsOneWidget);
      await capture(tester, captureKey, 'editor-context-desktop');
      await tester.tap(find.byKey(const ValueKey('editor.menu.移除链接')));
      await frames(tester);
      expect(editor.source, '<p>前<strong>原始链接</strong>后</p>');
      expect(editor.text, '前原始链接后');
      await tester.ensureVisible(find.byTooltip('撤销'));
      await tester.tap(find.byTooltip('撤销'));
      await frames(tester);
      expect(editor.source, contains('href="https://example.com/a"'));
      await selectLink(tester);
      await tester.tap(find.byKey(const ValueKey('editor.menu.group.段落')));
      await tester.pumpAndSettle();
      expect(find.text('左对齐'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('editor.menu.group.插入')));
      await tester.pumpAndSettle();
      expect(find.text('下载卡片'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('editor.menu.group.文字')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('editor.menu.字号')));
      await tester.tap(find.byKey(const ValueKey('editor.menu.字号')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('24 px'));
      await tester.pumpAndSettle();
      expect(editor.source, contains('<span style="font-size:24px">始链</span>'));
      expect(editor.source, contains('<a href='));
      expect(tester.takeException(), isNull);
      await close(tester, app);
    },
  );
  testWidgets(
    'desktop secondary click opens custom text menu and image actions',
    (tester) async {
      final app = await mount(tester);
      final field = find.byKey(const Key('editor.content'));
      final editor =
          tester.widget<TextField>(field).controller! as VisualHtmlController;
      await tester.enterText(field, '右键菜单测试');
      await tester.ensureVisible(field);
      await tester.tapAt(
        tester.getTopLeft(field) + const Offset(28, 25),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor.context.menu')), findsOneWidget);
      await tester.tap(find.byTooltip('关闭菜单'));
      editor.load(
        '<p>前<a href="https://example.com/page"><img src="https://example.com/pic.png" width="240" data-id="7"></a>后</p>',
      );
      editor.onSourceChanged?.call();
      await tester.pumpAndSettle();
      final image = find.byTooltip('右键编辑图片 · 地址、说明、尺寸或移除');
      await tester.ensureVisible(image);
      await tester.tap(image, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.text('替换图片'), findsOneWidget);
      await capture(tester, captureKey, 'editor-image-context-desktop');
      expect(find.text('编辑图片链接'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('editor.image.blur')));
      await tester.pumpAndSettle();
      expect(editor.source, contains('blur-img'));
      expect(editor.source, contains('width="240"'));
      expect(editor.source, contains('data-id="7"'));
      expect(editor.source, contains('href="https://example.com/page"'));
      expect(tester.takeException(), isNull);
      await close(tester, app);
    },
  );
  testWidgets(
    'phone long press opens bounded menu and all formatting groups are reachable',
    (tester) async {
      final app = await mount(tester, mobile: true);
      final field = find.byKey(const Key('editor.content'));
      await tester.enterText(field, '长按选择这里的文字');
      await tester.ensureVisible(field);
      await tester.longPressAt(tester.getTopLeft(field) + const Offset(36, 25));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor.context.menu')), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const Key('editor.context.menu'))).right,
        lessThanOrEqualTo(390),
      );
      await capture(tester, captureKey, 'editor-context-phone');
      final tab = find.byKey(const ValueKey('editor.menu.group.工具'));
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await tester.pumpAndSettle();
      expect(find.text('查找替换'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester, app);
    },
  );
  testWidgets(
    'blur applies only to article thumbnail, original viewer stays clear',
    (tester) async {
      final app = await mount(tester);
      final markup = extraToggleImageBlur(
        '<img src="https://example.com/a.png" width="200" class="custom">',
        true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DeskScope(
            app: app,
            open: (_) {},
            child: Scaffold(body: RichContent(markup)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ImageFiltered), findsOneWidget);
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(ImageFiltered),
        ),
        findsNothing,
      );
      await close(tester, app);
    },
  );
}
