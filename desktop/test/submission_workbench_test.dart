import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/browse_cache.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/core/submission_workbench.dart';
import 'package:xingyu_desktop/core/source_document.dart';
import 'package:xingyu_desktop/pages/submission_workbench.dart';
import 'package:xingyu_desktop/pages/cache_settings.dart';
import 'package:xingyu_desktop/ui/shared.dart';
import 'package:xingyu_desktop/ui/submission_categories.dart';

import 'ai_test.dart' show Client, Request, Reply;

import 'widget_test.dart' show FakeSite, FakeService, OfflineSocket, capture;

class CacheSite extends FakeSite {
  int calls = 0;
  Object? failure;
  Completer<Json>? pause;
  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) async {
    calls++;
    if (failure != null) throw failure!;
    if (pause != null) return pause!.future;
    return super.get(path, params);
  }
}

class CacheHttp extends Client {
  int calls = 0;
  CacheHttp() : super(Request(Reply('synthetic-image-bytes')));
  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    calls++;
    return super.openUrl('GET', url);
  }
}

AppState appFor([SiteApi? site]) =>
    AppState(
        siteApi: site ?? FakeSite(),
        serviceApi: FakeService(),
        socketFactory: OfflineSocket.new,
      )
      ..user = {...FakeSite.user}
      ..starting = false;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SecureVault.setMockInitialValues({});
    BrowseCache.shared.directory = null;
    BrowseCache.shared.enabled = true;
  });
  setUpAll(() async {
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
  test('full category catalog preserves arbitrary new/deep categories and ancestry', () {
    final catalog = fullCategoryPaths([
      {
        'id': 1,
        'name': '新大类',
        'children': [
          {
            'id': 2,
            'name': '新二级',
            'children': [
              {'id': 3, 'name': '新三级'},
            ],
          },
        ],
      },
    ]);
    expect(catalog.map((c) => c.label), [
      '新大类',
      '新大类 / 新二级',
      '新大类 / 新二级 / 新三级',
    ]);
    expect(catalog.last.ids, {1, 2, 3});
  });
  test('edits preserve inline links, images, download components, code and purchase proof', () {
    const source =
        '<p>原文 <a href="https://example.com">链接</a></p><p><img src="https://example.com/a.png"></p>[dlbox title="资源" link1="下载|https://example.com/file"][/dlbox]<pre>code 123</pre><div data-xingyu-purchase-proof="1"><p>自购证明</p><img src="https://example.com/proof.png"></div>';
    final doc = WorkDocument(source);
    expect(doc.segments.map((s) => s['text']), ['原文 ', '链接']);
    final result = doc.apply([
      {'id': '0', 'text': '译文 '},
    ]);
    expect(result, contains('https://example.com/a.png'));
    expect(
      result,
      contains(
        '[dlbox title="资源" link1="下载|https://example.com/file"][/dlbox]',
      ),
    );
    expect(result, contains('<pre>code 123</pre>'));
    expect(result, contains('https://example.com/proof.png'));
    expect(
      html.parseFragment(result).querySelector('a')!.attributes['href'],
      'https://example.com',
    );
    expect(
      () => WorkDocument(source).apply([
        {'id': '100', 'text': 'bad'},
      ]),
      throwsA(isA<ApiFailure>()),
    );
  });
  test('layout refuses text rewrites and can promote paragraphs without touching images', () {
    expect(
      () => WorkDocument('<p>标题</p>').apply([
        {'id': '0', 'text': '篡改', 'kind': 'h2'},
      ], layoutOnly: true),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      WorkDocument('<p>标题</p><p><img src="https://e.example/a.png"></p>')
          .apply([
            {'id': '0', 'text': '标题', 'kind': 'h2'},
          ], layoutOnly: true),
      contains('<h2>标题</h2>'),
    );
  });
  test('structural command moves introduction images before proof/downloads and retains all URLs', () {
    const source =
        '<p><img src="https://example.com/a.png"></p><p>正文</p><div data-xingyu-purchase-proof="1"><img src="https://example.com/proof.png"></div>[dlbox title="下载"][/dlbox]';
    final result = localSubmissionCommand(source, '把介绍图片放到正文后')!;
    expect(result.indexOf('正文'), lessThan(result.indexOf('a.png')));
    expect(result.indexOf('a.png'), lessThan(result.indexOf('proof.png')));
    expect(result.indexOf('proof.png'), lessThan(result.indexOf('[dlbox')));
    expect(localSubmissionCommand(source, '修正错别字'), isNull);
  });
  test('metadata requires verbatim evidence and schema refuses unknown/repeated paragraph edits', () {
    final request = {
      'task': 'metadata',
      'segments': [
        {'id': '0', 'text': '介绍'},
      ],
      'sources': [
        {'text': '作者：星屿\n发行日期：2026-10-23'},
      ],
    };
    final value = {
      'edits': [],
      'notes': ['已整理'],
      'metadata': [
        {'label': '作者', 'value': '星屿', 'source_id': 0, 'evidence': '作者：星屿'},
        {'label': '版本', 'value': '2.0', 'source_id': 0, 'evidence': '版本：2.0'},
      ],
    };
    expect(rows(parseWorkbench(value, request)['metadata']).length, 1);
    expect(
      () => parseWorkbench({
        ...value,
        'edits': [
          {'id': '0', 'text': '改写'},
        ],
      }, request),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      structuredSourceFields(rows(request['sources'])).map((f) => f['label']),
      ['作者', '发行日期'],
    );
  });
  test('source facts extraction sees DLsite-style tables outside intro without copying page navigation', () {
    final source = parseSourceDocument(
      '<h1>Original</h1><table><tr><th>サークル名</th><td>Circle A</td></tr><tr><th>販売日</th><td>2026年10月23日</td></tr></table><div id="work_description"><p>作品介绍</p></div>',
      Uri.parse(
        'https://www.dlsite.com/maniax/work/=/product_id/RJ12345678.html',
      ),
    );
    expect(source['facts'], contains('サークル名：Circle A'));
    expect(source['text'], '作品介绍');
    expect(structuredSourceFields([source]).map((f) => f['value']), [
      'Circle A',
      '2026年10月23日',
    ]);
  });
  test('download split keeps each code with its own link and handles query code and punctuation', () {
    final values = splitDownloadMaterial(
      '百度 https://pan.baidu.com/s/a 提取码：abcd\n夸克 https://pan.quark.cn/s/b 提取码：efgh\n解压密码：hello-123\nhttps://pan.baidu.com/s/c?pwd=ijkl。',
    );
    expect(values.map((v) => v.code), ['abcd', 'efgh', 'ijkl']);
    expect(values.first.password, 'hello-123');
    expect(values.last.url, endsWith('pwd=ijkl'));
  });
  test('preflight, translation evidence and duplicate searches avoid asserting completeness', () {
    expect(
      extraPreflight(
        '作品',
        '<p>待补充</p>',
        sourceUrls: [
          'https://www.dlsite.com/maniax/work/=/product_id/RJ12345678.html',
        ],
      ).join(),
      contains('RJ12345678'),
    );
    expect(
      translationChecks([
        {
          'text': '120 minutes, 10 tracks',
          'blocks': [
            {'kind': 'image', 'url': 'https://example.com/a.png'},
          ],
        },
      ], '<p>时长 12 分钟</p>').join(),
      contains('120'),
    );
    expect(duplicateQueries('[音声] Original [RJ12345678]', []), [
      'RJ12345678',
      'Original',
    ]);
  });
  test('habits only adjust text styles and preserve proof and shortcode data', () {
    const source =
        '<p>正文</p><div data-xingyu-purchase-proof="1"><p>自购证明</p></div>[dlbox title="原卡片"][/dlbox]';
    final result = applySubmissionHabits(source, {
      'font': 18,
      'lineHeight': 2.0,
      'compact': true,
    });
    final doc = html.parseFragment(result);
    expect(
      doc.querySelector('p')!.attributes['style'],
      contains('font-size:18px'),
    );
    expect(doc.querySelector('div p')!.attributes['style'], isNull);
    expect(result, contains('[dlbox title="原卡片"][/dlbox]'));
  });
  test('disk cache survives new store, scopes accounts and evicts oldest within capacity', () async {
    final directory = await Directory.systemTemp.createTemp(
      'xingyu-cache-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = BrowseCache(
      directory: directory,
      maxBytes: 30,
      maxEntries: 2,
    );
    await store.write('a', List.filled(12, 1));
    await store.write('b', List.filled(12, 2));
    await store.write('c', List.filled(12, 3));
    expect(await store.read('a'), isNull);
    expect((await store.size()).bytes, lessThanOrEqualTo(30));
    expect(
      await BrowseCache(directory: directory).read('c'),
      List.filled(12, 3),
    );
    expect(
      browsingKey(1, 'post/info', {'id': 1}),
      isNot(browsingKey(2, 'post/info', {'id': 1})),
    );
    expect(cacheableRead('auth/me', {}), false);
    expect(cacheableRead('post/info', {'exclude_view': 1}), false);
    expect(cacheableRead('post/list', {'status': 'draft'}), false);
  });
  test(
    'clear invalidates in-flight writes without deleting unrelated local files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'xingyu-cache-clear-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = BrowseCache(directory: directory);
      final epoch = store.epoch;
      await File('${directory.path}/draft.json').writeAsString('keep');
      await store.write('old', [1]);
      await store.clear();
      await store.write('late', [2], generation: epoch);
      expect(await store.read('late'), isNull);
      expect((await store.size()).entries, 0);
      expect(await File('${directory.path}/draft.json').readAsString(), 'keep');
    },
  );
  test('AppState reuses disk browsing cache, refreshes, falls back offline, rejects auth fallback', () async {
    final directory = await Directory.systemTemp.createTemp(
      'xingyu-state-cache-',
    );
    addTearDown(() async {
      await BrowseCache.shared.size(); // Drain queued writes before removing the test directory.
      BrowseCache.shared.directory = null;
      await directory.delete(recursive: true);
    });
    BrowseCache.shared.directory = directory;
    final site = CacheSite(), app = appFor(site);
    addTearDown(app.dispose);
    await app.get('post/info', {'id': 1});
    await app.get('post/info', {'id': 1});
    expect(site.calls, 1);
    app.refreshBrowsing();
    await app.get('post/info', {'id': 1});
    expect(site.calls, 2);
    site.failure = const SocketException('offline');
    expect((await app.get('post/info', {'id': 1}))['_xingyu_offline'], true);
    site.failure = ApiFailure(401, 'expired');
    await expectLater(
      app.get('post/info', {'id': 1}),
      throwsA(isA<ApiFailure>()),
    );
    expect(app.uid, 0);
  });
  test('late account response never populates another account cache', () async {
    final directory = await Directory.systemTemp.createTemp(
      'xingyu-cache-account-',
    );
    addTearDown(() async {
      await BrowseCache.shared.size(); // Drain queued writes before removing the test directory.
      BrowseCache.shared.directory = null;
      await directory.delete(recursive: true);
    });
    BrowseCache.shared.directory = directory;
    final site = CacheSite()..pause = Completer<Json>(), app = appFor(site);
    addTearDown(app.dispose);
    final pending = app.get('post/info', {'id': 8});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    app.user = {'id': 88};
    app.generation++;
    site.pause!.complete({
      'data': {'id': 8},
    });
    await expectLater(pending, throwsA(isA<ApiFailure>()));
    expect((await BrowseCache.shared.size()).entries, 0);
  });
  test(
    'image cache avoids repeat downloads and honors disable switch',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'xingyu-image-cache-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final cache = BrowseCache(directory: directory), client = CacheHttp();
      await HttpOverrides.runZoned(() async {
        final first = await cache.image('https://example.com/image.png');
        expect(first, isNotEmpty);
        expect(await cache.image('https://example.com/image.png'), first);
        expect(client.calls, 1);
        cache.enabled = false;
        await cache.image('https://example.com/image.png');
        expect(client.calls, 2);
        expect(await cache.read('image:https://example.com/image.png'), isNull);
      }, createHttpClient: (_) => client);
    },
  );
  testWidgets('cached page displays refresh action without layout overflow', (
    tester,
  ) async {
    final app = appFor();
    addTearDown(app.dispose);
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DeskScope(
          app: app,
          open: (_) {},
          child: Scaffold(
            body: AsyncPane(
              load: () async {
                loads++;
                return {'_xingyu_cache': true, '_xingyu_offline': true};
              },
              builder: (_, _) => ListView(children: const [Text('缓存作品')]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('网络暂不可用，正在显示本机缓存'), findsOneWidget);
    await tester.tap(find.text('刷新'));
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(app.bypassCacheUntil.isAfter(DateTime.now()), true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'cache settings can clear browsing cache while retaining local drafts and habits',
    (tester) async {
      final app = appFor()
        ..local = {
          'drafts': {
            '47': {
              'new': {'title': '保留草稿'},
            },
          },
          'submissionHabits': {
            '47': {'font': 18},
          },
        };
      addTearDown(app.dispose);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: CacheSettings(app))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('清理缓存'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '清理'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(find.text('浏览缓存已清理'), findsOneWidget);
      expect(app.drafts['new']['title'], '保留草稿');
      expect(app.submissionHabits['font'], 18);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final width in [390.0, 1280.0]) {
    testWidgets('toolbox and full category selector fit $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = appFor();
      app.categories = rows((await app.site.get('category/list'))['data']);
      addTearDown(app.dispose);
      final shot = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            fontFamily: 'Microsoft YaHei UI',
            useMaterial3: true,
          ),
          home: DeskScope(
            app: app,
            open: (_) {},
            child: RepaintBoundary(
              key: shot,
              child: Scaffold(
                body: SubmissionWorkbench(
                  app: app,
                  title: '[测试] Original',
                  body: '<p>作品介绍</p>',
                  initialTask: 'download',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (width < 640) {
        await tester.tap(find.text('切换工具'));
        await tester.pumpAndSettle();
      }
      expect(find.text('疑似重复投稿'), findsOneWidget);
      if (width < 640) {
        await tester.tap(find.text('收起'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await capture(tester, shot, 'submission-toolbox-${width.round()}');
      await tester.enterText(
        find.widgetWithText(TextField, '分享信息'),
        'https://pan.baidu.com/s/test 提取码：abcd',
      );
      await tester.ensureVisible(find.text('本机拆分并预览'));
      await tester.tap(find.text('本机拆分并预览'));
      await tester.pumpAndSettle();
      expect(find.textContaining('未识别'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: DeskScope(
            app: app,
            open: (_) {},
            child: Scaffold(
              body: Builder(
                builder: (c) => TextButton(
                  onPressed: () => showSubmissionCategories(c, app, {}),
                  child: const Text('选择'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '搜索分类'), '故事');
      await tester.pumpAndSettle();
      expect(find.text('灵感收藏 / 故事'), findsOneWidget);
      await tester.tap(find.text('灵感收藏 / 故事'));
      await tester.pumpAndSettle();
      expect(find.textContaining('已选 2 项'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
