import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/ai.dart';
import 'package:xingyu_desktop/core/browse_cache.dart';
import 'package:xingyu_desktop/core/html_cleanup.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/reader.dart';
import 'package:xingyu_desktop/core/source_document.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/core/submission_guidance.dart';
import 'package:xingyu_desktop/core/submission_workbench.dart';
import 'package:xingyu_desktop/core/translation.dart';
import 'package:xingyu_desktop/core/video_source.dart';
import 'package:xingyu_desktop/core/visual_editor.dart';
import 'package:xingyu_desktop/pages/authoring.dart';
import 'package:xingyu_desktop/pages/reading.dart';
import 'package:xingyu_desktop/ui/inline_video.dart';
import 'package:xingyu_desktop/ui/shared.dart';

import 'widget_test.dart'
    show FakeSite, FakeService, OfflineSocket, frames, capture;

class DraftSite extends FakeSite {
  final bool wrongOwner;
  Json? previewParams;
  int writes = 0;
  DraftSite({this.wrongOwner = false});
  static Json fixturePost(bool other) => {
    'id': 123,
    'user_id': other ? 99 : 47,
    'user': {...FakeSite.user},
    'title': '作者专属的测试草稿',
    'status': 'draft',
    'created_at': '2026-10-23',
    'content': '<h2>草稿预览</h2><p>这篇作品尚未公开。</p>',
    'categories': <Json>[],
  };
  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) async {
    if (path == 'post/list') {
      return {
        'code': 0,
        'data': [fixturePost(false)],
        'meta': {'current_page': 1, 'last_page': 1},
      };
    }
    if (path == 'post/info') {
      previewParams = {...?params};
      return {'code': 0, 'data': fixturePost(wrongOwner)};
    }
    return super.get(path, params);
  }

  @override
  Future<Json> post(String path, [Json? body]) async {
    writes++;
    return {'code': 0};
  }
}

AppState appFor(DraftSite site) =>
    AppState(
        siteApi: site,
        serviceApi: FakeService(),
        socketFactory: OfflineSocket.new,
      )
      ..starting = false
      ..user = {...FakeSite.user};

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
  test('deleting all visible content removes empty list, heading and anchor HTML', () {
    final editor = VisualHtmlController()
      ..load(
        '<h3>作品资料</h3><ul>${List.generate(18, (i) => '<li>字段$i</li>').join()}</ul><h3>来源</h3><ul><li><a href="https://example.com">链接</a></li></ul>',
      );
    editor.value = const TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
    );
    expect(editor.source.trim(), isEmpty);
    expect(editor.text.trim(), isEmpty);
    editor.value = const TextEditingValue(
      text: '重新输入😀',
      selection: TextSelection.collapsed(offset: 6),
    );
    expect(editor.source, '重新输入😀');
    editor.dispose();
  });
  test('partial deletion prunes empty items and keeps media, code and source bytes outside edits', () {
    const tail =
        '<p data-keep="x"><img src="https://example.com/a.png"></p><video src="https://example.com/a.mp4"></video>[dlbox title="保留"][/dlbox]<pre><code>&lt;li&gt;&lt;/li&gt;</code></pre>';
    final editor = VisualHtmlController()
      ..load('<ul><li>删除</li><li>保留</li></ul>$tail');
    editor.value = TextEditingValue(
      text: editor.text.replaceFirst('删除', ''),
      selection: const TextSelection.collapsed(offset: 0),
    );
    expect(editor.source, startsWith('<ul><li>保留</li></ul>'));
    expect(editor.source, endsWith(tail));
    expect(editor.text, contains('\uFFFC'));
    editor.dispose();
    const old =
        '<h3></h3><ul><li><a href="https://example.com"></a></li><li>&nbsp;</li><li><br></li></ul><p></p>';
    expect(removeEmptyEditingMarkup(old), isEmpty);
    expect(
      html
          .parseFragment(ReaderDocument.parse(old).content)
          .querySelectorAll('li'),
      isEmpty,
    );
  });
  test('formal DLsite type wins over unrelated story keywords and unknown types stay unknown', () async {
    final guide = await SubmissionGuidance.load();
    for (final (code, expected) in [
      ('RPG', 'game'),
      ('SOU', 'asmr'),
      ('MNG', 'doujin'),
      ('MOV', 'animation'),
      ('ICG', 'pictures'),
      ('NRE', 'novel'),
      ('MUS', 'music'),
    ]) {
      final source = parseSourceDocument(
        '<h1>原作タイトル</h1><div id="category_type"><a href="/home/works/type/=/work_type/$code/from/icon.work">形式</a><span class="icon_MV2">動画あり</span></div><div id="work_description"><p>紹介: ASMRと漫画も登場する物語</p></div>',
        Uri.parse(
          'https://www.dlsite.com/home/work/=/product_id/RJ000001.html',
        ),
      );
      expect(guide.guess([source]), expected);
    }
    expect(
      guide.guess([
        {'facts': '作品形式：マンガ', 'title': '', 'text': ''},
      ]),
      'comic',
    );
    expect(
      guide.guess([
        {'url': 'https://example.com/work', 'title': '不明', 'text': ''},
      ]),
      'other',
    );
  });
  test('Steam API metadata is retained with publisher, localized date and current streaming trailers', () {
    final source = parseSteamSource({
      'name': 'Original Title',
      'type': 'game',
      'header_image': 'https://cdn.example.com/header.jpg',
      'detailed_description': '<p>First</p><video src="https://cdn.example.com/inline.webm"></video><p>Second</p>',
      'developers': ['Studio A', 'Studio B'],
      'publishers': ['Publisher C'],
      'release_date': {'date': '2026 年 10 月 23 日'},
      'movies': [
        {
          'name': 'Trailer',
          'hls_h264': 'https://cdn.example.com/master.m3u8?x=1&y=2',
          'thumbnail': 'https://cdn.example.com/movie.jpg',
        },
      ],
    }, Uri.parse('https://store.steampowered.com/app/123/'));
    final fields = structuredSourceFields([source]);
    expect(
      fields.firstWhere((f) => f['label'] == '开发商')['value'],
      'Studio A / Studio B',
    );
    expect(
      fields.firstWhere((f) => f['label'] == '发行商')['value'],
      'Publisher C',
    );
    expect(
      fields.firstWhere((f) => f['label'] == '发行日期')['value'],
      '2026 年 10 月 23 日',
    );
    expect(rows(source['blocks']).map((b) => b['kind']), [
      'p',
      'video',
      'p',
      'video',
    ]);
    expect(source['work_type'], 'game');
  });
  test('DLsite ordered video, lazy iframe and direct sources survive both translation paths', () {
    final source = parseSourceDocument(
      '<h1>原名</h1><div class="work_parts_container"><p>Before</p><video poster="https://cdn.example.com/p.jpg"><source src="https://cdn.example.com/movie.mp4"></video></div><div class="work_parts_container"><iframe data-src="https://chobit.cc/embed/abcde" title="体験動画"></iframe><p>After</p></div>',
      Uri.parse('https://www.dlsite.com/home/work/=/product_id/RJ000001.html'),
    );
    final blocks = rows(source['blocks']);
    expect(blocks.map((b) => b['kind']), ['p', 'video', 'video', 'p']);
    final request = translationRequest([source], 'extra', 'game', 'test');
    final wire = builtinBodyOnlyRequest(request);
    expect(rows(rows(wire['sources']).single['blocks']).map((b) => b['kind']), [
      'p',
      'p',
    ]);
    final restored = restoreOriginalSourceTitles({
      'title': '',
      'sources': [
        {'url': source['url']},
      ],
      'blocks': [
        {'kind': 'p', 'text': '之前'},
        {'kind': 'p', 'text': '之后'},
        {'kind': 'p', 'text': '补充'},
      ],
    }, request);
    expect(rows(restored['blocks']).map((b) => b['kind']), [
      'p',
      'video',
      'video',
      'p',
      'p',
    ]);
    final built = AiDraft.parse(restored, [source]);
    expect(
      built.body,
      contains('<video controls muted playsinline preload="none"'),
    );
    expect(
      built.body,
      contains('<iframe src="https:&#47;&#47;chobit.cc&#47;embed&#47;abcde"'),
    );
    final plan = TranslationPlan([source]), values = <String, String>{};
    for (final c in plan.chunks) {
      for (final segment in c) {
        values[text(segment['id'])] = text(segment['text']);
      }
    }
    expect(
      rows(plan.assemble([source], 'game', values)['blocks'])[1],
      blocks[1],
    );
    final reader = ReaderDocument.parse(built.body).content;
    expect(
      html.parseFragment(reader).querySelectorAll('.xingyu-video').length,
      2,
    );
    expect(reader, isNot(contains('<iframe')));
    final shortcode = ReaderDocument.parse(
      '[iframe]https://chobit.cc/embed/abcde[/iframe]',
    ).content;
    expect(shortcode, contains('xingyu-video'));
    expect(shortcode, isNot(contains('系统浏览器')));
  });
  test('public embedded player HTML resolves real media, never script execution or private URLs', () {
    expect(
      playableVideoFromHtml(
        '<video data-poster="https://cdn.example.com/p.jpg"><source src="https://file.chobit.cc/movie.mp4" type="video/mp4"></video>',
        Uri.parse('https://chobit.cc/embed/abcde'),
      ),
      'https://file.chobit.cc/movie.mp4',
    );
    expect(
      playableVideoFromHtml(
        '''<video data-setup='{"sources":[{"src":"https://cdn.example.com/master.m3u8"}]}'></video>''',
        Uri.parse('https://chobit.cc/embed/abcde'),
      ),
      'https://cdn.example.com/master.m3u8',
    );
    expect(
      () => playableVideoFromHtml(
        '<video src="file:///secret.mp4"></video><script>location="https://cdn.example.com/a.mp4"</script>',
        Uri.parse('https://chobit.cc/embed/abcde'),
      ),
      throwsA(isA<ApiFailure>()),
    );
  });
  for (final width in [390.0, 1280.0]) {
    testWidgets('management has labeled private draft preview at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final site = DraftSite(), app = appFor(DraftSite());
      final managedApp = appFor(site);
      DeskRoute? opened;
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            theme: ThemeData(
              fontFamily: 'Microsoft YaHei UI',
              colorScheme: ColorScheme.fromSeed(seedColor: violet),
            ),
            home: DeskScope(
              app: managedApp,
              open: (r) => opened = r,
              child: const Scaffold(
                body: AuthoringPage(
                  DeskRoute('manage', '投稿与管理', filter: 'draft'),
                ),
              ),
            ),
          ),
        ),
      );
      await frames(tester);
      expect(find.text('查看草稿'), findsOneWidget);
      await tester.ensureVisible(find.text('查看草稿'));
      await tester.tap(find.text('查看草稿'));
      await frames(tester);
      expect(opened?.filter, 'private-preview');
      expect(opened?.id, 123);
      expect(site.writes, 0);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'authoring-draft-$width');
      await tester.pumpWidget(const SizedBox());
      managedApp.dispose();
      app.dispose();
    });
  }
  testWidgets(
    'private preview refuses a different owner and does not cache, track history or expose share',
    (tester) async {
      final site = DraftSite(wrongOwner: true), app = appFor(site);
      await tester.pumpWidget(
        MaterialApp(
          home: DeskScope(
            app: app,
            open: (_) {},
            child: const Scaffold(body: ArticlePage(123, ownerOnly: true)),
          ),
        ),
      );
      await frames(tester);
      expect(find.text('仅作者本人可以查看这篇草稿'), findsOneWidget);
      expect(find.text('这篇作品尚未公开。'), findsNothing);
      expect(site.previewParams?['exclude_view'], 1);
      expect(site.writes, 0);
      expect(app.history, isEmpty);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
  testWidgets(
    'own draft and inline native video stay inside page without browser controls',
    (tester) async {
      final site = DraftSite(), app = appFor(site);
      await tester.pumpWidget(
        MaterialApp(
          home: DeskScope(
            app: app,
            open: (_) {},
            child: const Scaffold(body: ArticlePage(123, ownerOnly: true)),
          ),
        ),
      );
      await frames(tester);
      expect(find.text('作者专属预览 · 未公开内容仅本人可见'), findsOneWidget);
      expect(find.byTooltip('复制作品链接'), findsNothing);
      expect(app.history, isEmpty);
      expect(site.writes, 0);
      await tester.pumpWidget(
        MaterialApp(
          home: DeskScope(
            app: app,
            open: (_) {},
            child: Scaffold(
              body: SingleChildScrollView(
                child: RichContent(
                  preloadVideos: false,
                  ReaderDocument.parse(
                    '<video src="https://cdn.example.com/a.mp4" title="示例视频"></video>',
                  ).content,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InlineArticleVideo), findsOneWidget);
      expect(find.text('播放视频'), findsOneWidget);
      expect(find.textContaining('默认静音'), findsOneWidget);
      expect(find.textContaining('浏览器'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
