import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/ai.dart';
import 'package:xingyu_desktop/core/browse_cache.dart';
import 'package:xingyu_desktop/core/category_suggestion.dart';
import 'package:xingyu_desktop/core/image_codec.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/core/submission_guidance.dart';
import 'package:xingyu_desktop/pages/ai_assistant.dart';
import 'package:xingyu_desktop/pages/authoring.dart';
import 'package:xingyu_desktop/ui/shared.dart';

import 'widget_test.dart'
    show FakeSite, FakeService, OfflineSocket, frames, capture;

final tree = <Json>[
  {
    'id': 100,
    'name': '游戏',
    'children': [
      {'id': 101, 'name': '汉化'},
      {'id': 102, 'name': '生肉'},
    ],
  },
  {
    'id': 200,
    'name': '音乐',
    'children': [
      {'id': 210, 'name': '侍寝声音'},
    ],
  },
  {'id': 900, 'name': '隐藏分类'},
];

class CategoryTransport extends AiTransport {
  int calls = 0;
  Json? request;
  @override
  Future<Json> source(String raw) async => {
    'url': raw,
    'title': 'Original title',
    'work_type': 'game',
    'cover': '',
    'facts': 'Developer：Example Studio',
    'text': '这是用于测试的公开作品介绍。',
    'blocks': [
      {'kind': 'p', 'text': '这是用于测试的公开作品介绍。'},
    ],
  };
  @override
  Future<Json> json(
    Uri uri, {
    Json? body,
    String token = '',
    int max = 4 * 1024 * 1024,
    bool builtin = false,
    Duration timeout = const Duration(seconds: 120),
    String accept = 'application/json',
  }) async {
    calls++;
    request = body;
    return {
      'result': {
        'edits': [],
        'metadata': [],
        'notes': [
          jsonEncode({
            'category_ids': [102],
            'reason': '用户明确填写资源属性为生肉，选官网对应分类。',
          }),
        ],
      },
    };
  }
}

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
  test('source recommendations include parents, and store language never invents resource edition', () async {
    final guide = await SubmissionGuidance.load();
    expect(sourceCategorySuggestion(guide, tree, 'game'), {100});
    expect(
      sourceCategorySuggestion(guide, [
        {
          'id': 100,
          'name': '游戏',
          'children': [
            {'id': 101, 'name': '汉化'},
          ],
        },
      ], 'game'),
      {100},
    );
    expect(sourceCategorySuggestion(guide, tree, 'game', traits: '生肉'), {
      100,
      102,
    });
    expect(sourceCategorySuggestion(guide, tree, 'asmr'), {200, 210});
    expect(categorySelectionLabel(tree, {100, 102}), '游戏 / 生肉');
    expect(sourceCategorySuggestion(guide, tree, 'other'), isEmpty);
  });
  test('AI classifier uses supported preflight protocol and rejects foreign, hidden or unsupported edition IDs', () async {
    final guide = await SubmissionGuidance.load();
    final request = categoryCheckRequest(
      guide,
      tree,
      'game',
      [
        {'url': 'https://example.com', 'text': '作品介绍'},
      ],
      '原作',
      '生肉',
    );
    Json answer(List<int> ids) => {
      'edits': [],
      'metadata': [],
      'notes': [
        jsonEncode({'category_ids': ids, 'reason': '分类依据'}),
      ],
    };
    expect(request['task'], 'preflight');
    expect(parseCategoryCheck(answer([102]), request, tree, '生肉').ids, {
      100,
      102,
    });
    for (final ids in [
      [9999],
      [900],
      [210],
    ]) {
      expect(
        () => parseCategoryCheck(answer(ids), request, tree, '生肉'),
        throwsA(isA<ApiFailure>()),
      );
    }
    expect(
      () => parseCategoryCheck(answer([101]), request, tree, ''),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      () => parseCategoryCheck(
        {
          'edits': [],
          'metadata': [],
          'notes': ['聊天或错误返回'],
        },
        request,
        tree,
        '',
      ),
      throwsA(isA<ApiFailure>()),
    );
  });
  test('AVIF detection uses file brands, including animated AVIS, rather than URL suffix', () {
    Uint8List ftyp(String brand) => Uint8List.fromList([
      0,
      0,
      0,
      24,
      ...ascii.encode('ftyp'),
      ...ascii.encode('mif1'),
      0,
      0,
      0,
      0,
      ...ascii.encode(brand),
      ...ascii.encode('miaf'),
    ]);
    expect(isAvif(ftyp('avif')), true);
    expect(isAvif(ftyp('avis')), true);
    expect(isAvif(ftyp('jpeg')), false);
    expect(isAvif(Uint8List(7)), false);
  });
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'AI classification and confirmed import reach editor categories at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
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
              ..categories = tree
              ..identity = {
                'token': 'synthetic-token',
                'expires_at': DateTime.now()
                    .add(const Duration(days: 1))
                    .toIso8601String(),
              };
        final shot = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: shot,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                fontFamily: 'Microsoft YaHei UI',
                colorScheme: ColorScheme.fromSeed(seedColor: violet),
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
        final entry = find.widgetWithText(FilledButton, 'AI 投稿助手');
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pumpAndSettle();
        final dynamic state = tester.state(find.byType(AiAssistantDialog));
        state.transport.close();
        final io = CategoryTransport();
        state.transport = io;
        state.links.text = 'https://store.steampowered.com/app/123/';
        await tester.ensureVisible(find.text('提取介绍'));
        await tester.tap(find.text('提取介绍'));
        await tester.pumpAndSettle();
        expect(state.proposedCategories, {100});
        expect(state.importCategories, true);
        state.guideAttributes.text = '生肉';
        await tester.ensureVisible(find.text('官网规范 · 标题与分类辅助'));
        await tester.tap(find.text('官网规范 · 标题与分类辅助'));
        await tester.pumpAndSettle();
        final auto = find.byKey(const Key('ai.categories.auto'));
        await tester.ensureVisible(auto);
        await tester.tap(auto);
        await tester.pumpAndSettle();
        expect(io.calls, 1);
        expect(io.request?['task'], 'preflight');
        expect(state.proposedCategories, {100, 102});
        expect(state.importCategories, true);
        await capture(tester, shot, 'category-ai-${width.toInt()}');
        final original = find.widgetWithText(CheckboxListTile, '正文无需翻译');
        await tester.ensureVisible(original);
        await tester.tap(original);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('生成草稿'));
        await tester.tap(find.text('生成草稿'));
        await tester.pumpAndSettle();
        final selection = find.widgetWithText(CheckboxListTile, '使用已确认分类');
        expect(tester.widget<CheckboxListTile>(selection).value, true);
        await tester.ensureVisible(find.text('导入草稿'));
        await tester.tap(find.text('导入草稿'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '导入'));
        await tester.pumpAndSettle();
        expect(find.text('分类 · 2'), findsOneWidget);
        expect(io.calls, 1);
        final dynamic editor = tester.state(find.byType(PostEditor));
        expect(editor.categories, {100, 102});
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      },
    );
  }
}
