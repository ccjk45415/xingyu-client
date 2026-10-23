import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/ai.dart';
import 'package:xingyu_desktop/core/browse_cache.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/pages/authoring.dart';
import 'package:xingyu_desktop/pages/ai_assistant.dart';
import 'package:xingyu_desktop/pages/submission_workbench.dart';
import 'package:xingyu_desktop/ui/shared.dart';

import 'widget_test.dart'
    show FakeSite, FakeService, OfflineSocket, frames, capture;

class QuerySite extends FakeSite {
  final queries = <String>[];
  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) {
    if (path == 'post/search') queries.add(text(params?['search']));
    return super.get(path, params);
  }
}

AppState appFor(QuerySite site) =>
    AppState(
        siteApi: site,
        serviceApi: FakeService(),
        socketFactory: OfflineSocket.new,
      )
      ..user = {...FakeSite.user}
      ..starting = false
      ..local = {
        'drafts': {
          '47': {
            'new': {
              'title': '[软件] 原作标题 [RJ01699082]',
              'content': '<p>第一段原文</p><p>第二段原文</p>',
              'content_format': 'html',
              'editor_mode': 'source',
            },
          },
        },
        'submissionHabits': {
          '47': {'enabled': true, 'font': 24, 'lineHeight': 2.0},
        },
      };

void main() {
  setUp(() {
    SecureVault.setMockInitialValues({});
    BrowseCache.shared.directory = null;
  });
  setUpAll(() async {
    await rootBundle.loadString('assets/submission-guidance.json');
    for (final (family, path) in [
      ('Microsoft YaHei UI', 'C:/Windows/Fonts/msyh.ttc'),
      (
        'MaterialIcons',
        'C:/codex-tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ),
    ]) {
      if (File(path).existsSync()) {
        await (FontLoader(
          family,
        )..addFont(File(path).readAsBytes().then(ByteData.sublistView))).load();
      }
    }
  });
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'one AI entry, editable duplicate input and preserved sections at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 950);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final site = QuerySite();
        final state = appFor(site);
        addTearDown(state.dispose);
        final shot = GlobalKey();
        final opened = <DeskRoute>[];
        await tester.pumpWidget(
          RepaintBoundary(
            key: shot,
            child: MaterialApp(
              theme: ThemeData(
                fontFamily: 'Microsoft YaHei UI',
                useMaterial3: true,
              ),
              home: DeskScope(
                app: state,
                open: opened.add,
                child: const Scaffold(
                  body: PostEditor(DeskRoute('editor', '新建投稿')),
                ),
              ),
            ),
          ),
        );
        await frames(tester);
        await tester.pumpAndSettle();
        expect(find.text('AI 投稿助手'), findsOneWidget);
        expect(find.text('投稿工具箱'), findsNothing);
        expect(find.text('处理选中文字'), findsNothing);
        await tester.ensureVisible(find.text('AI 投稿助手'));
        await tester.tap(find.text('AI 投稿助手'));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AiAssistantHub), findsOneWidget);
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text('资料与翻译'), findsOneWidget);
        expect(find.text('编辑与检查'), findsOneWidget);
        final links = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '作品链接',
        );
        await tester.ensureVisible(links);
        await tester.enterText(links, 'https://example.com/original');
        await tester.tap(find.text('编辑与检查'));
        await tester.pumpAndSettle();
        if (width < 640) {
          await tester.tap(find.text('切换工具'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('疑似重复投稿').first);
        await tester.pumpAndSettle();
        final query = find.byKey(const Key('ai.duplicate.query'));
        await tester.ensureVisible(query);
        expect(
          tester.widget<TextField>(query).controller!.text,
          contains('RJ01699082'),
        );
        expect(
          tester.widget<TextField>(query).controller!.text,
          contains('原作标题'),
        );
        await tester.enterText(query, '');
        await tester.ensureVisible(find.text('检索官网投稿'));
        await tester.tap(find.text('检索官网投稿'));
        await tester.pumpAndSettle();
        expect(find.text('请在上方填写作品名称或 RJ 号'), findsOneWidget);
        await tester.enterText(query, 'RJ12345678');
        await tester.tap(find.text('检索官网投稿'));
        await frames(tester);
        await tester.pumpAndSettle();
        expect(site.queries, ['RJ12345678']);
        await tester.ensureVisible(query);
        await capture(tester, shot, 'ai-unified-duplicate-${width.round()}');
        await tester.tap(find.text('资料与翻译'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(links).controller!.text,
          'https://example.com/original',
        );
        await tester.tap(find.text('编辑与检查'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(query).controller!.text, 'RJ12345678');
        expect(find.byType(Dialog), findsOneWidget);
        final candidate = find.text(text(FakeSite.posts.first['title'])).first;
        await tester.ensureVisible(candidate);
        await tester.tap(candidate);
        await tester.pumpAndSettle();
        expect(opened.single.id, 1);
        expect(find.byType(AiAssistantHub), findsNothing);
        final title = find.byWidgetPredicate(
          (w) =>
              w is TextField && w.controller?.text == '[软件] 原作标题 [RJ01699082]',
        );
        expect(title, findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'unified edit section receives exact selection, preserves styles and can undo',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = appFor(QuerySite());
      addTearDown(app.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: DeskScope(
            app: app,
            open: (_) {},
            child: const Scaffold(
              body: PostEditor(DeskRoute('editor', '新建投稿')),
            ),
          ),
        ),
      );
      await frames(tester);
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('editor.content'));
      final controller = tester.widget<TextField>(field).controller!;
      final original = controller.text;
      controller.selection = const TextSelection(
        baseOffset: 3,
        extentOffset: 6,
      );
      await tester.ensureVisible(find.text('AI 投稿助手'));
      await tester.tap(find.text('AI 投稿助手'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑与检查'));
      await tester.pumpAndSettle();
      final tools = tester.widget<SubmissionWorkbench>(
        find.byType(SubmissionWorkbench),
      );
      expect(tools.selection!.a, 3);
      expect(tools.selection!.b, 6);
      final changed = original.replaceFirst('第一段', '修改段');
      tools.onApply!(WorkbenchChange(changed));
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistantHub), findsNothing);
      expect(controller.text, changed);
      expect(controller.text, isNot(contains('font-size:24')));
      await tester.ensureVisible(find.byTooltip('撤销'));
      await tester.tap(find.byTooltip('撤销'));
      await tester.pumpAndSettle();
      expect(controller.text, original);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'editing generated draft updates preview and leaves editor draft untouched',
    (tester) async {
      final app = appFor(QuerySite());
      addTearDown(app.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: DeskScope(
            app: app,
            open: (_) {},
            child: Scaffold(
              body: AiAssistantHub(
                app,
                editorTitle: '原标题',
                editorBody: '<p>编辑器原稿</p>',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      final dynamic generator = tester.state(find.byType(AiAssistantDialog));
      generator.sources = <Json>[
        {
          'url': 'https://example.com/work',
          'title': 'Original',
          'text': '作品原文',
          'blocks': <Json>[
            {'kind': 'p', 'text': '作品原文'},
          ],
        },
      ];
      generator.keepOriginal = true;
      await generator.generate();
      await tester.pumpAndSettle();
      expect((generator.draft as AiDraft).title, 'Original');
      await tester.tap(find.text('编辑与检查'));
      await tester.pumpAndSettle();
      final tools = tester.widget<SubmissionWorkbench>(
        find.byType(SubmissionWorkbench),
      );
      expect(tools.body, contains('作品原文'));
      tools.onApply!(const WorkbenchChange('<p>修改后的草稿</p>'));
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistantHub), findsOneWidget);
      expect((generator.draft as AiDraft).body, '<p>修改后的草稿</p>');
      expect(app.drafts['new']['content'], '<p>第一段原文</p><p>第二段原文</p>');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
