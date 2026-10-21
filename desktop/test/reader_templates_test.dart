import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;
import 'package:xingyu_desktop/core/reader.dart';
import 'package:xingyu_desktop/ui/shared.dart';

void main() {
  testWidgets(
    'website collapse and blackbar are native interactive preview components',
    (tester) async {
      final doc = ReaderDocument.parse(
        '<p>[collapse title="折叠标题"]</p><p>折叠正文</p><p>[/collapse]</p><p><span class="text-forbidden">隐藏文字测试</span></p>',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RichContent(doc.content, fontSize: 16),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('折叠标题'), findsOneWidget);
      expect(find.textContaining('折叠正文', findRichText: true), findsNothing);
      await tester.tap(find.text('折叠标题'));
      await tester.pumpAndSettle();
      expect(find.textContaining('折叠正文', findRichText: true), findsWidgets);
      await tester.tap(find.text('点击显示隐藏文字'));
      await tester.pumpAndSettle();
      expect(find.textContaining('隐藏文字测试', findRichText: true), findsWidgets);
    },
  );
  test('complete download metadata and repeated link names survive in order', () {
    const source =
        '<p>before</p>[dlbox title="标题 &amp; 名字" time="2026-10-21" info="提取：abc / 密码：123" from="本人上传" link1="网盘|https://example.com/one" link2="网盘|https://example.com/two"][/dlbox]<p>after</p>';
    final doc = ReaderDocument.parse(source, inlineResources: true),
        box = doc.resources.single;
    expect(box.time, '2026-10-21');
    expect(box.from, '本人上传');
    expect(box.details, contains('提取：abc / 密码：123'));
    expect(box.links.values, [
      'https://example.com/one',
      'https://example.com/two',
    ]);
    expect(doc.content, contains('文件来源：本人上传'));
    expect(
      doc.content.indexOf('before'),
      lessThan(doc.content.indexOf('xingyu-download')),
    );
    expect(html.parseFragment(doc.content).querySelectorAll('a').map((e) => e.attributes['href']), ['https://example.com/one', 'https://example.com/two']);
    expect(html.parseFragment(doc.content).text?.endsWith('after'), true);
  });
  test('external embeds become explicit safe browser links without executing content', () {
    final doc = ReaderDocument.parse(
      '[iframe]https://store.steampowered.com/app/1[/iframe][iframe]javascript:bad()[/iframe]',
    );
    expect(doc.content, contains('在系统浏览器打开'));
    expect(html.parseFragment(doc.content).querySelector('a')?.attributes['href'], 'https://store.steampowered.com/app/1');
    expect(doc.content, isNot(contains('javascript:')));
    expect(doc.content, contains('外部链接无效'));
  });
  test('code examples remain literal and ordinary collapse preserves body and title', () {
    const code =
        '<pre><code>[dlbox title="示例"][/dlbox][iframe]https://example.com[/iframe]</code></pre>';
    final doc = ReaderDocument.parse(
      '$code[collapse title="更多 &amp; 说明" show="true"]<p>正文</p>[/collapse]',
    );
    expect(doc.resources, isEmpty);
    expect(doc.content, startsWith(code));
    expect(doc.content, contains('<details open>'));
    expect(doc.content, contains('<summary>更多 &amp; 说明</summary>'));
    expect(doc.content, contains('<p>正文</p>'));
  });
}
