import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:xingyu_desktop/core/reader.dart';
import 'package:xingyu_desktop/core/visual_editor.dart';
import 'package:xingyu_desktop/ui/editor_templates.dart';

void main() {
  const card =
      '[dlbox title="资源下载" info="提取：0721" link1="百度网盘|https://pan.baidu.com/s/example"][/dlbox]';
  test(
    'rich-text deletion clears list scaffolding before download insertion',
    () {
      final visual = VisualHtmlController()
        ..load('<ul><li>第一项</li><li>第二项</li><li>第三项</li><li>第四项</li></ul>');
      addTearDown(visual.dispose);
      visual.value = const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
      expect(html.parseFragment(visual.source).querySelectorAll('li'), isEmpty);
      final document = ReaderDocument.parse(
        '${visual.source}\n$card',
        inlineResources: true,
      );
      expect(
        html.parseFragment(document.content).querySelectorAll('li'),
        isEmpty,
      );
      expect(document.resources.single.info, '提取：0721');
      expect(
        document.resources.single.links.values.single,
        'https://pan.baidu.com/s/example',
      );
    },
  );
  test('cleanup preserves genuine text, media, links, nested list data and code examples', () {
    const original =
        '<ul><li><br></li><li><a href="https://example.com/deleted-label"></a></li><li>&nbsp;</li><li><p><strong> </strong></p></li><li>真实内容</li><li><img src="https://example.com/a.png"></li><li><a href="https://example.com">链接</a></li><li><ul><li>嵌套内容</li><li><br></li></ul></li></ul><pre>&lt;ul&gt;&lt;li&gt;&lt;/li&gt;&lt;/ul&gt;</pre>';
    final clean = removeEmptyListPlaceholders(original),
        doc = html.parseFragment(clean);
    expect(doc.querySelectorAll('li').length, 5);
    expect(doc.text, contains('真实内容'));
    expect(doc.text, contains('嵌套内容'));
    expect(
      doc.querySelector('img')!.attributes['src'],
      'https://example.com/a.png',
    );
    expect(doc.querySelector('a')!.attributes['href'], 'https://example.com');
    expect(doc.querySelector('pre')!.text, '<ul><li></li></ul>');
  });
  test('newly generated download cards have no list placeholders and preserve sharing details', () {
    final generated = downloadTemplate(
      title: '下载资源',
      code: '0721',
      password: 'test-pass',
      links: [(name: '百度网盘', url: 'https://pan.baidu.com/s/example?pwd=0721')],
    );
    final body =
        '${removeEmptyListPlaceholders('<ol><li><br></li><li>\u200b</li></ol>')}\n$generated';
    expect(html.parseFragment(body).querySelectorAll('li'), isEmpty);
    final doc = ReaderDocument.parse(body, inlineResources: true);
    expect(doc.resources.length, 1);
    expect(doc.resources.single.info, '提取：0721 / 密码：test-pass');
    expect(
      doc.resources.single.links.values.single,
      'https://pan.baidu.com/s/example?pwd=0721',
    );
  });
}
