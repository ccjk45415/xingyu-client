import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/core/submission_extras.dart';
import 'package:xingyu_desktop/pages/ai_assistant.dart';

import 'widget_test.dart'
    show FakeSite, FakeService, OfflineSocket, frames, capture;

const dlsite =
    'https://www.dlsite.com/maniax-touch/work/=/product_id/RJ01699082.html';
const proof = 'https://file.cangku.moe/images/synthetic-proof.jpg?a=1&b=2';

class ProofSite extends FakeSite {
  final uploads = <(String, String, int)>[];
  bool fail = false;
  @override
  Future<Json> upload(
    String path,
    String field,
    Uint8List bytes, [
    Json fields = const {},
  ]) async {
    uploads.add((path, field, bytes.length));
    if (fail) throw ApiFailure(503, '测试上传失败');
    return {
      'code': 0,
      'data': {'url': proof},
    };
  }
}

void main() {
  setUpAll(() async {
    await rootBundle.loadString('assets/submission-guidance.json');
    for (final (name, path) in [
      ('Microsoft YaHei UI', 'C:/Windows/Fonts/msyh.ttc'),
      (
        'MaterialIcons',
        'C:/codex-tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ),
    ]) {
      final f = File(path);
      if (f.existsSync()) {
        await (FontLoader(
          name,
        )..addFont(f.readAsBytes().then(ByteData.sublistView))).load();
      }
    }
  });
  test('RJ tags preserve original names, deduplicate and reject lookalike hosts or arbitrary URL text', () {
    expect(withDlsiteIds('原作 😀', [dlsite, dlsite]), '原作 😀 [RJ01699082]');
    expect(withDlsiteIds('原作 [rj01699082]', [dlsite]), '原作 [rj01699082]');
    expect(withDlsiteIds('', [dlsite]), '');
    for (final link in [
      'https://dlsite.com.example.com/product_id/RJ01699082.html',
      'https://example.com/?url=$dlsite',
      'https://dlsite.com@evil.com/product_id/RJ01699082.html',
      'https://www.dlsite.com/path?product_id=RJ01699082',
      'https://www.dlsite.com/product_id/RJ01699082.html.evil',
    ]) {
      expect(withDlsiteIds('原作', [link]), '原作');
    }
    expect(
      withDlsiteIds('原作', [
        dlsite,
        'https://www.dlsite.com/maniax/work/=/product_id/RJ123456.html',
      ]),
      '原作 [RJ01699082] [RJ123456]',
    );
  });
  test('proof sits after introduction and before real download, preserves source, replaces only previous proof', () {
    const intro =
        '<p>原文 <b>格式 &amp; 内容</b></p><pre>[dlbox title="example"]</pre><!-- [dlbox] -->';
    const downloads =
        '<p>[dlbox title="真实下载" link1="测试|https://example.com"][/dlbox]</p><p>尾部不变</p>';
    final body = placePurchaseProof('$intro$downloads', proof);
    expect(body.startsWith(intro), true);
    expect(body.endsWith(downloads), true);
    expect(
      body.indexOf('data-xingyu-purchase-proof'),
      greaterThan(body.indexOf('</pre>')),
    );
    expect(
      body.indexOf('data-xingyu-purchase-proof'),
      lessThan(body.indexOf(downloads)),
    );
    expect(body, contains('?a=1&amp;b=2'));
    final twice = placePurchaseProof(body, 'https://file.cangku.moe/new.jpg');
    expect(RegExp('data-xingyu-purchase-proof').allMatches(twice).length, 1);
    expect(twice, isNot(contains('synthetic-proof.jpg')));
    expect(twice, contains(downloads));
    expect(placePurchaseProof(intro, proof).startsWith(intro), true);
    expect(
      () => placePurchaseProof(intro, 'javascript:bad'),
      throwsA(isA<ApiFailure>()),
    );
    final merged = mergeSubmissionBody(
      '$intro$downloads',
      '<p>AI忠实介绍</p>',
      true,
      proof,
    );
    expect(
      merged.indexOf('AI忠实介绍'),
      lessThan(merged.indexOf('data-xingyu-purchase-proof')),
    );
    expect(
      merged.indexOf('data-xingyu-purchase-proof'),
      lessThan(merged.indexOf(downloads)),
    );
    expect(
      mergeSubmissionBody('$intro$downloads', '新正文', true, null),
      '$intro$downloads\n新正文',
    );
  });
  for (final width in [1280.0, 430.0]) {
    testWidgets(
      'purchase proof official upload, required import, RJ and label layout $width',
      (tester) async {
        SecureVault.setMockInitialValues({});
        final site = ProofSite();
        final app =
            AppState(
                siteApi: site,
                serviceApi: FakeService(),
                socketFactory: OfflineSocket.new,
              )
              ..starting = false
              ..user = Map.from(FakeSite.user);
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(app.dispose);
        Future<void> reveal(Finder f) async {
          await tester.pumpAndSettle();
          await tester.ensureVisible(f);
          await tester.pumpAndSettle();
        }

        final screen = GlobalKey();
        AiImport? imported;
        await tester.pumpWidget(
          RepaintBoundary(
            key: screen,
            child: MaterialApp(
              theme: ThemeData(fontFamily: 'Microsoft YaHei UI'),
              home: Scaffold(
                body: Builder(
                  builder: (c) => TextButton(
                    onPressed: () async {
                      imported = await showDialog<AiImport>(
                        context: c,
                        builder: (_) => AiAssistantDialog(
                          app,
                          proofPicker: (_) async =>
                              Uint8List.fromList([1, 2, 3]),
                        ),
                      );
                    },
                    child: const Text('助手'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('助手'));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 150)),
        );
        await frames(tester);
        await tester.pumpAndSettle();
        Finder field(String label) => find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == label,
        );
        final links = field('作品链接');
        await reveal(links);
        await tester.enterText(links, dlsite);
        await reveal(find.text('手动粘贴'));
        await tester.tap(find.text('手动粘贴'));
        await tester.pumpAndSettle();
        final original = find.byWidgetPredicate(
          (w) =>
              w is TextFormField &&
              w.key.toString().contains('ai.source.0.title.'),
        );
        await reveal(original);
        await tester.enterText(original, '原作タイトル 😀');
        final body = find.byWidgetPredicate(
          (w) =>
              w is TextFormField &&
              w.key.toString().contains('ai.source.0.body.'),
        );
        await reveal(body);
        await tester.enterText(body, '介绍保持原样。');
        await reveal(find.text('正文无需翻译'));
        await tester.tap(find.text('正文无需翻译'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('生成草稿'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(field('投稿标题')).controller!.text,
          '原作タイトル 😀 [RJ01699082]',
        );
        await reveal(find.text('官网规范 · 标题与分类辅助'));
        await tester.tap(find.text('官网规范 · 标题与分类辅助'));
        await tester.pumpAndSettle();
        final kind = find.byKey(const ValueKey('guide.kind.other'));
        await reveal(kind);
        expect(
          tester.getRect(find.text('作品类型')).bottom,
          lessThan(tester.getRect(kind).top),
        );
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(kind)
              .decoration
              .labelText,
          isNull,
        );
        expect(
          tester.getRect(find.text('作品类型')).left,
          closeTo(tester.getRect(kind).left, 1),
        );
        final category = find.byKey(const ValueKey('guide.path.other.'));
        await reveal(category);
        expect(
          tester.getRect(find.text('投稿分类')).bottom,
          lessThan(tester.getRect(category).top),
        );
        await reveal(find.text('作品类型'));
        await capture(tester, screen, 'desktop-ai-fields-${width.toInt()}');
        final purchased = find.byKey(const Key('ai.selfPurchased'));
        expect(tester.widget<CheckboxListTile>(purchased).value, false);
        await reveal(purchased);
        await tester.tap(purchased);
        await tester.pumpAndSettle();
        await tester.tap(find.text('导入草稿'));
        await tester.pumpAndSettle();
        expect(find.text('导入这份草稿？'), findsNothing);
        expect(imported, isNull);
        expect(find.text('自购资源请先上传一张自购证明'), findsOneWidget);
        await reveal(find.text('上传自购证明'));
        await tester.tap(find.text('上传自购证明'));
        await tester.pumpAndSettle();
        expect(site.uploads, [('upload/image', 'image', 3)]);
        expect(find.text('更换证明图片'), findsOneWidget);
        await reveal(purchased);
        await capture(tester, screen, 'desktop-ai-purchase-${width.toInt()}');
        // Failed replacement retains the last successfully uploaded picture.
        site.fail = true;
        await reveal(find.text('更换证明图片'));
        await tester.tap(find.text('更换证明图片'));
        await tester.pumpAndSettle();
        expect(find.text('测试上传失败'), findsOneWidget);
        await tester.tap(find.text('导入草稿'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '导入'));
        await tester.pumpAndSettle();
        expect(imported, isNotNull);
        expect(imported!.purchaseProof, proof);
        expect(imported!.suggestedTitle, '原作タイトル 😀 [RJ01699082]');
        expect(
          imported!.draft.data.toString(),
          isNot(contains(proof)),
        ); // Never put receipt into AI data.
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 200));
      },
    );
  }
}
