import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/app.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/browse_cache.dart';
import 'package:xingyu_desktop/core/dynamic_template_store.dart';
import 'package:xingyu_desktop/core/dynamic_templates.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/pages/account_overview.dart';
import 'package:xingyu_desktop/pages/dynamic_templates.dart';
import 'package:xingyu_desktop/ui/shared.dart';

import 'support/system_test_fonts.dart';

const templateWidgetTree = <Json>[
  {
    'id': 100,
    'name': '游戏',
    'children': [
      {'id': 101, 'name': '汉化'},
      {'id': 102, 'name': '生肉'},
    ],
  },
];

class DynamicWidgetSite extends SiteApi {
  int sourceReads = 0, writes = 0;
  Json? latest;
  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) async {
    if (path == 'post/info') {
      sourceReads++;
      if (latest != null) return {'data': latest};
      return {
        'data': {
          'id': 123,
          'title': 'Original Synthetic Game',
          'thumb': 'https://file.cangku.moe/images/synthetic-cover.png',
          'content': '<h3>作品介绍</h3><p>这是用于界面验证的合成游戏作品，支持自由探索与故事体验。</p>',
          'categories': [
            {'id': 100, 'name': '游戏'},
          ],
        },
      };
    }
    if (path == 'category/list') return {'data': templateWidgetTree};
    return {'data': []};
  }

  @override
  Future<Json> post(String path, Json body) async {
    writes++;
    throw StateError('This UI test must never submit to the website');
  }
}

class DynamicWidgetApp extends AppState {
  DynamicWidgetApp(DynamicWidgetSite site) : super(siteApi: site);
  @override
  Future<void> persist() async {}
}

Finder templateTab(String label) => find
    .descendant(
      of: find.byType(SegmentedButton<int>),
      matching: find.text(label),
    )
    .first;

Finder templateField(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

Future<void> localFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> dynamicCapture(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> selectTemplateTab(WidgetTester tester, String label) async {
  await tester.ensureVisible(templateTab(label));
  await tester.tap(templateTab(label));
  await tester.pumpAndSettle();
}

Future<void> openTemplateLibrary(WidgetTester tester, double width) async {
  if (width < 1050) {
    await tester.tap(find.text('模板与任务'));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUpAll(() async {
    await rootBundle.loadString('assets/submission-guidance.json');
    await loadSystemTestFonts();
  });
  setUp(() async {
    SecureVault.setMockInitialValues({});
    BrowseCache.shared.directory = null;
    await BrowseCache.shared.clear();
  });

  for (final (websiteStatus, expectedStatus) in [
    ('publish', 'publish'),
    ('future', 'future'),
    ('rejected', 'pending'),
  ]) {
    testWidgets('website $websiteStatus retains status and protects full body', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = Directory.systemTemp.createTempSync(
        'xingyu-template-full-',
      );
      final task = newDynamicTask(starterDynamicTemplates().first)
        ..['post_id'] = 123
        ..['needs_latest'] = true
        ..['desired_status'] = 'draft'
        ..['category_ids'] = [100]
        ..['fields'] = {
          'title': '旧版任务资料',
          'description': '旧版介绍',
          'cover': 'https://file.cangku.moe/images/old-cover.png',
          'source_urls': ['https://cangku.moe/archives/123'],
          'purchased': true,
          'proof': 'https://file.cangku.moe/images/old-proof.png',
          'downloads': [
            {'name': '旧链接', 'url': 'https://pan.baidu.com/s/old'},
          ],
        };
      const finalBody =
          '<h3>官网完整正文</h3><p data-id="latest">最终人工排版和媒体组件</p>'
          '[dlbox title="最终下载" link1="新链接|https://pan.baidu.com/s/final"][/dlbox]';
      final site = DynamicWidgetSite()
        ..latest = {
          'id': 123,
          'user_id': 47,
          'title': '官网最终原标题',
          'content': finalBody,
          'thumb': 'https://file.cangku.moe/images/final-cover.png',
          'tags': [],
          'status': websiteStatus,
          'updated_at': '2026-11-01T01:00:00Z',
          'created_at': '2030-01-02T01:02:03Z',
          'categories': [
            {'id': 100, 'name': '游戏'},
          ],
        };
      final app = DynamicWidgetApp(site)
        ..directory = directory
        ..categories = templateWidgetTree
        ..user = {'id': 47, 'nickname': '普通投稿作者'};
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await localFrames(tester);
        app.dispose();
        await tester.runAsync(() async {
          if (await directory.exists()) await directory.delete(recursive: true);
        });
      });
      await tester.runAsync(() async {
        final journal = await DynamicTemplateStore.open(
          47,
          directory: directory,
        );
        try {
          journal.saveTask(task);
        } finally {
          journal.close();
        }
      });
      Json? opened;
      await tester.pumpWidget(
        MaterialApp(
          theme: XingyuApp(app: app).theme(Brightness.light),
          home: DeskScope(
            app: app,
            open: (_) {},
            child: Scaffold(
              body: DynamicTemplatesPage(
                app,
                onOpenDraft: (id, snapshot, postId) async {
                  opened = snapshot;
                },
              ),
            ),
          ),
        ),
      );
      await localFrames(tester);
      await tester.ensureVisible(find.text('旧版任务资料'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('旧版任务资料'));
      await tester.pumpAndSettle();
      await selectTemplateTab(tester, '资料');
      Finder materialsScroll() => find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('载入官网最新内容'),
        500,
        scrollable: materialsScroll(),
      );
      await tester.tap(find.text('载入官网最新内容'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('载入最新内容'));
      await tester.pumpAndSettle();
      final state = tester.state<ScrollableState>(materialsScroll());
      state.position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(templateField('作品介绍')).enabled, false);
      expect(
        tester.widget<TextField>(templateField('作品介绍')).controller!.text,
        contains('最终人工排版和媒体组件'),
      );
      expect(find.textContaining('正文图片、自购证明、下载信息'), findsOneWidget);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, '这是自购作品'),
            )
            .onChanged,
        isNull,
      );
      await tester.scrollUntilVisible(
        find.widgetWithText(OutlinedButton, '添加下载信息'),
        400,
        scrollable: materialsScroll(),
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, '添加下载信息'),
            )
            .onPressed,
        isNull,
      );
      await selectTemplateTab(tester, '预览');
      final confirmButton = find.byKey(const Key('dynamic.preview.confirm'));
      await tester.ensureVisible(confirmButton);
      await tester.pumpAndSettle();
      expect(confirmButton.hitTestable(), findsOneWidget);
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();
      expect(opened?['status'], expectedStatus);
      expect(opened?['content'], finalBody);
      expect(
        opened?['schedule'],
        websiteStatus == 'future' ? '2030-01-02 09:02:03' : '',
      );
      expect(site.writes, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'creator keeps old entries and exposes dynamic templates at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final site = DynamicWidgetSite();
        final app = DynamicWidgetApp(site)
          ..user = {'id': 47, 'nickname': '测试投稿作者'};
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await localFrames(tester);
          app.dispose();
        });
        DeskRoute? opened;
        await tester.pumpWidget(
          MaterialApp(
            theme: XingyuApp(app: app).theme(Brightness.light),
            home: DeskScope(
              app: app,
              open: (r) => opened = r,
              child: const Scaffold(body: AccountOverview()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('我的投稿'), findsOneWidget);
        expect(find.text('本机草稿'), findsOneWidget);
        expect(find.byKey(const Key('account.new-post')), findsOneWidget);
        final templateEntry = find
            .ancestor(of: find.text('动态模板'), matching: find.byType(InkWell))
            .first;
        await tester.ensureVisible(templateEntry);
        await tester.pumpAndSettle();
        await tester.tap(templateEntry);
        expect(opened?.kind, 'dynamicTemplates');
        await tester.ensureVisible(find.byKey(const Key('account.new-post')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('account.new-post')));
        expect(opened?.kind, 'editor');
        expect(site.writes, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('dynamic template workflow, versions and recovery at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = Directory.systemTemp.createTempSync(
        'xingyu-template-widget-',
      );
      final site = DynamicWidgetSite();
      final app = DynamicWidgetApp(site)
        ..directory = directory
        ..categories = templateWidgetTree
        ..user = {'id': 47, 'nickname': '测试投稿作者'};
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await localFrames(tester);
        app.dispose();
        await tester.runAsync(() async {
          if (await directory.exists()) await directory.delete(recursive: true);
        });
      });
      final shot = GlobalKey();
      final opened = <Json>[];
      Future<void> mount() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: XingyuApp(app: app).theme(Brightness.light),
            home: DeskScope(
              app: app,
              open: (_) {},
              child: RepaintBoundary(
                key: shot,
                child: Scaffold(
                  body: DynamicTemplatesPage(
                    app,
                    key: ValueKey('dynamic-test-${app.uid}'),
                    onOpenDraft: (id, snapshot, postId) async {
                      opened.add({
                        'task': id,
                        'snapshot': snapshot,
                        'post': postId,
                      });
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await localFrames(tester);
        expect(find.byKey(const Key('dynamic.message')), findsOneWidget);
      }

      await mount();
      await openTemplateLibrary(tester, width);
      final gameTemplate = find.byKey(
        const ValueKey('dynamic.template.starter.game'),
      );
      await tester.ensureVisible(gameTemplate);
      await tester.tap(gameTemplate);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      await dynamicCapture(
        tester,
        shot,
        'dynamic-template-chat-${width.toInt()}',
      );

      await selectTemplateTab(tester, '预览');
      final confirmButton = find.byKey(const Key('dynamic.preview.confirm'));
      expect(tester.widget<FilledButton>(confirmButton).onPressed, isNull);
      expect(opened, isEmpty);

      await selectTemplateTab(tester, '对话');
      await tester.enterText(
        find.byKey(const Key('dynamic.message')),
        '作品名：Original Synthetic Game\n'
        '作品介绍：这是用于测试的游戏介绍，包含探索和故事内容。\n'
        '作品链接：https://cangku.moe/archives/123\n'
        '网盘链接：https://pan.baidu.com/s/synthetic\n'
        '提取码：abcd\n不是自购',
      );
      await tester.tap(find.widgetWithText(FilledButton, '发送'));
      await tester.pumpAndSettle();
      expect(site.sourceReads, 1);
      expect(find.textContaining('资料已齐全'), findsOneWidget);
      await selectTemplateTab(tester, '资料');
      expect(
        tester.widget<TextField>(templateField('作品原标题')).controller!.text,
        'Original Synthetic Game',
      );
      await tester.enterText(templateField('作品原标题'), 'Original Game Final');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await dynamicCapture(
        tester,
        shot,
        'dynamic-template-materials-${width.toInt()}',
      );

      await selectTemplateTab(tester, '预览');
      expect(tester.widget<FilledButton>(confirmButton).onPressed, isNotNull);
      await dynamicCapture(
        tester,
        shot,
        'dynamic-template-preview-${width.toInt()}',
      );
      await tester.ensureVisible(confirmButton);
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();
      expect(opened, hasLength(1));
      final savedSnapshot = object(opened.single['snapshot']);
      expect(savedSnapshot['title'], 'Original Game Final');
      expect(savedSnapshot['content'], contains('这是用于测试的游戏介绍'));
      expect(savedSnapshot['content'], contains('pan.baidu.com/s/synthetic'));
      expect(savedSnapshot['category_ids'], contains(100));
      expect(savedSnapshot['dynamic_template_version'], 1);
      expect(site.writes, 0);

      await openTemplateLibrary(tester, width);
      await tester.ensureVisible(gameTemplate);
      await tester.tap(
        find.descendant(
          of: gameTemplate,
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑与保存新版本'));
      await tester.pumpAndSettle();
      await tester.enterText(templateField('模板名称'), '我的游戏投稿格式');
      await tester.tap(find.text('保存模板'));
      await tester.pumpAndSettle();
      if (width < 1050) {
        Navigator.of(tester.element(find.byType(BottomSheet))).pop();
        await tester.pumpAndSettle();
      }
      await tester.runAsync(() async {
        final journal = await DynamicTemplateStore.open(
          47,
          directory: directory,
        );
        try {
          expect(journal.versions('starter.game'), hasLength(2));
          expect(
            journal.templates.firstWhere((t) => t.id == 'starter.game').name,
            '我的游戏投稿格式',
          );
          final task = journal.task(text(opened.single['task']))!;
          expect(object(task['template'])['version'], 1);
          expect(object(task['template'])['name'], '游戏分享');
          expect(
            journal
                .messages(text(task['id']))
                .where((m) => m['role'] == 'user'),
            hasLength(1),
          );
        } finally {
          journal.close();
        }
      });

      await tester.pumpWidget(const SizedBox());
      await mount();
      await openTemplateLibrary(tester, width);
      final existingTask = find.text('Original Game Final');
      await tester.ensureVisible(existingTask);
      await tester.tap(existingTask);
      await tester.pumpAndSettle();
      if (find.byType(BottomSheet).evaluate().isNotEmpty) {
        Navigator.of(tester.element(find.byType(BottomSheet))).pop();
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('不是自购'), findsWidgets);
      await selectTemplateTab(tester, '资料');
      expect(
        tester.widget<TextField>(templateField('作品原标题')).controller!.text,
        'Original Game Final',
      );

      await tester.pumpWidget(const SizedBox());
      app.user = {'id': 48, 'nickname': '另一个投稿作者'};
      await mount();
      await openTemplateLibrary(tester, width);
      expect(find.text('Original Game Final'), findsNothing);
      expect(find.text('我的游戏投稿格式'), findsNothing);
      expect(find.text('游戏分享'), findsOneWidget);
      expect(site.writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
