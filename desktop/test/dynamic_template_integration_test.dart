import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/browse_cache.dart';
import 'package:xingyu_desktop/core/dynamic_template_store.dart';
import 'package:xingyu_desktop/core/dynamic_templates.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/pages/authoring.dart';
import 'package:xingyu_desktop/ui/shared.dart';

import 'widget_test.dart' show FakeSite, FakeService, OfflineSocket, frames;

class TemplateEditorSite extends FakeSite {
  final writes = <(String, Json)>[];
  Json latest = {
    ...FakeSite.posts.first,
    'id': 321,
    'updated_at': '2026-11-01T01:00:00Z',
  };

  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) async {
    if (path == 'post/info') return {'data': latest};
    return super.get(path, params);
  }

  @override
  Future<Json> post(String path, Json body) async {
    writes.add((path, {...body}));
    return {
      'data': {'id': 321, 'status': body['status']},
    };
  }
}

class TemplateEditorApp extends AppState {
  TemplateEditorApp(TemplateEditorSite site)
    : super(
        siteApi: site,
        serviceApi: FakeService(),
        socketFactory: OfflineSocket.new,
      );

  // The local draft map is exercised; actual SQLite persistence is verified
  // separately below, without unrelated library.json writes in fake async time.
  @override
  Future<void> persist() async {}
}

Json fixtureTask() {
  final task = newDynamicTask(starterDynamicTemplates().first);
  task['id'] = 'synthetic-template-task';
  task['fields'] = {
    'title': '测试原始标题',
    'description': '这是合成的投稿介绍。',
    'purchased': false,
  };
  task['desired_status'] = 'pending';
  return task;
}

AppState fixtureApp(TemplateEditorSite site, Json snapshot) =>
    TemplateEditorApp(site)
      ..starting = false
      ..user = {...FakeSite.user}
      ..local = {
        'drafts': {
          '47': {'dynamic-fixture': snapshot},
        },
      };

Finder get titleField => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == '一个吸引人的标题…',
);

Future<void> mountEditor(
  WidgetTester tester,
  AppState app, {
  int postId = 0,
  void Function(DeskRoute)? open,
}) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: DeskScope(
        app: app,
        open: open ?? (_) {},
        child: Scaffold(
          body: PostEditor(
            DeskRoute('editor', '模板投稿预览', id: postId, query: 'dynamic-fixture'),
          ),
        ),
      ),
    ),
  );
  await frames(tester);
}

Future<void> submitFixture(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, '提交到网站');
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pumpAndSettle();
  expect(find.text('确认提交'), findsOneWidget);
  await tester.tap(find.text('确认提交'));
  for (var i = 0; i < 12; i++) {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await rootBundle.loadString('assets/submission-guidance.json');
  });
  setUp(() {
    SecureVault.setMockInitialValues({});
    BrowseCache.shared.directory = null;
  });

  testWidgets(
    'template metadata survives editor autosave in its original account',
    (tester) async {
      final site = TemplateEditorSite(), task = fixtureTask();
      final snapshot = dynamicEditorSnapshot(task, 47)
        ..['baseline'] = 'keep-existing-baseline'
        ..['version'] = 'keep-existing-version';
      final app = fixtureApp(site, snapshot);
      addTearDown(app.dispose);
      await mountEditor(tester, app);
      await tester.enterText(titleField, '手动修改后的模板投稿');
      await tester.pump(const Duration(milliseconds: 700));
      final saved = object(app.drafts['dynamic-fixture']);
      expect(saved['dynamic_task_id'], task['id']);
      expect(saved['dynamic_template_id'], 'starter.game');
      expect(saved['dynamic_template_version'], 1);
      expect(saved['baseline'], 'keep-existing-baseline');
      expect(saved['version'], 'keep-existing-version');
      expect(saved['title'], '手动修改后的模板投稿');

      app.user = {...FakeSite.user, 'id': 48};
      app.generation++;
      await tester.enterText(titleField, '旧编辑器的最后一次保存');
      await tester.pump(const Duration(milliseconds: 700));
      expect(app.drafts, isEmpty);
      final oldDraft = object(
        object(object(app.local['drafts'])['47'])['dynamic-fixture'],
      );
      expect(oldDraft['owner'], 47);
      expect(oldDraft['dynamic_task_id'], task['id']);
      expect(site.writes, isEmpty);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmed submission records final manual edits and website post ID',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'xingyu-template-editor-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final site = TemplateEditorSite(), task = fixtureTask();
      await tester.runAsync(() async {
        final store = await DynamicTemplateStore.open(47, directory: directory);
        store.saveTask(task);
        store.close();
      });
      final app = fixtureApp(site, dynamicEditorSnapshot(task, 47))
        ..directory = directory;
      addTearDown(app.dispose);
      DeskRoute? opened;
      await mountEditor(tester, app, open: (r) => opened = r);
      await tester.enterText(titleField, '最终人工确认的作品标题');
      final body = find.byKey(const Key('editor.content'));
      await tester.ensureVisible(body);
      await tester.enterText(body, '人工编辑后的最终正文，使用本机合成资料。');
      await submitFixture(tester);
      expect(site.writes.single.$1, 'post/create');
      expect(site.writes.single.$2['title'], '最终人工确认的作品标题');
      expect(opened?.kind, 'manage');
      expect(app.drafts.containsKey('dynamic-fixture'), false);
      await tester.runAsync(() async {
        final store = await DynamicTemplateStore.open(47, directory: directory);
        final saved = store.task(text(task['id']))!;
        expect(saved['post_id'], 321);
        expect(saved['status'], 'pending');
        expect(object(saved['fields'])['title'], '最终人工确认的作品标题');
        expect(object(saved['fields'])['body_html'], contains('人工编辑后的最终正文'));
        expect(object(saved['editor_snapshot'])['dynamic_task_id'], task['id']);
        expect(
          store.search('最终人工确认').where((r) => r['kind'] == 'submission'),
          hasLength(1),
        );
        store.close();
        final other = await DynamicTemplateStore.open(48, directory: directory);
        expect(other.task(text(task['id'])), isNull);
        expect(other.search('最终人工确认'), isEmpty);
        other.close();
      });
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unavailable independent task journal does not turn website success into failure',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'xingyu-template-journal-failure-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      // Only the independent journal path is unavailable; library autosave works.
      File('${directory.path}/dynamic-templates')
          .writeAsStringSync('synthetic occupied path');
      final site = TemplateEditorSite();
      final app = fixtureApp(site, dynamicEditorSnapshot(fixtureTask(), 47))
        ..directory = directory;
      addTearDown(app.dispose);
      DeskRoute? opened;
      await mountEditor(tester, app, open: (r) => opened = r);
      await submitFixture(tester);
      expect(site.writes.single.$1, 'post/create');
      expect(opened?.kind, 'manage');
      expect(find.textContaining('若提交超时'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a template draft preserves conflict baseline and cannot overwrite newer website content',
    (tester) async {
      final site = TemplateEditorSite(), task = fixtureTask();
      task['post_id'] = 321;
      final snapshot = dynamicEditorSnapshot(task, 47)
        ..['version'] = '2026-10-30T01:00:00Z'
        ..['baseline'] = 'snapshot-from-an-older-website-version'
        ..['oldStatus'] = 'publish';
      final app = fixtureApp(site, snapshot);
      addTearDown(app.dispose);
      await mountEditor(tester, app, postId: 321);
      await submitFixture(tester);
      expect(site.writes, isEmpty);
      expect(find.textContaining('网站内容已在别处变更'), findsOneWidget);
      expect(
        object(app.drafts['dynamic-fixture'])['baseline'],
        'snapshot-from-an-older-website-version',
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
