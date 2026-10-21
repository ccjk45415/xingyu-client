import 'dart:math';

import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;

import '../core/api.dart';

const extraFontNames = [
  '默认字体',
  '宋体',
  '黑体',
  '微软雅黑',
  '仿宋',
  '楷体',
  'Arial',
  'Georgia',
  'Impact',
  'Tahoma',
  'Times New Roman',
  'Verdana',
];
const extraFonts = [
  '',
  'SimSun, STSong, sans-serif',
  'SimHei, STHeiti, sans-serif',
  '"Microsoft YaHei", sans-serif',
  'FangSong, STFangsong, sans-serif',
  'KaiTi, STKaiti, sans-serif',
  'Arial,Helvetica,sans-serif',
  'Georgia,serif',
  'Impact,Charcoal,sans-serif',
  'Tahoma,Geneva,sans-serif',
  '"Times New Roman",Times,serif',
  'Verdana,Geneva,sans-serif',
];
const extraEmoji = [
  '😀',
  '😊',
  '😍',
  '🥰',
  '😎',
  '🤔',
  '😭',
  '😅',
  '👍',
  '👏',
  '🙏',
  '❤️',
  '💜',
  '✨',
  '🎉',
  '🎮',
  '🎧',
  '📚',
  '🌸',
  '⭐',
  '(｡･ω･｡)',
  '(๑•̀ㅂ•́)و✧',
];
const extraSpecial = [
  '©',
  '®',
  '™',
  '°',
  '±',
  '×',
  '÷',
  '≠',
  '≤',
  '≥',
  '∞',
  '√',
  'π',
  'Ω',
  'α',
  'β',
  'γ',
  'δ',
  '←',
  '→',
  '↑',
  '↓',
  '↔',
  '⇒',
  '★',
  '☆',
  '♥',
  '♡',
  '◆',
  '◇',
  '•',
  '…',
  '—',
  '§',
  '¶',
  '€',
  '£',
  '¥',
  '＜',
  '＞',
  '＆',
];
String extraEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
String extraFont(int index, String selection) {
  if (index < 0 || index >= extraFonts.length) {
    throw const FormatException('字体无效');
  }
  return index == 0
      ? selection
      : '<span style="font-family: ${extraEscape(extraFonts[index])};">$selection</span>';
}

String extraLineHeight(String value, String selection) {
  if (!['1', '1.15', '1.5', '1.75', '2', '2.5', '3'].contains(value)) {
    throw const FormatException('行高无效');
  }
  return '<div style="line-height: $value;">$selection</div>';
}

String extraInline(String kind, String selection) {
  if (!['text-rainbow', 'text-forbidden'].contains(kind)) {
    throw const FormatException('样式无效');
  }
  return '<span class="$kind">$selection</span>';
}

String extraCollapse(String title, String body, bool expanded) {
  if (title.trim().isEmpty || body.trim().isEmpty) {
    throw const FormatException('请填写标题和内容');
  }
  final safe = extraEscape(title.replaceAll('[', '【').replaceAll(']', '】'));
  return '<p>[collapse title="$safe"${expanded ? ' show="true"' : ''}]</p>\n<p>${extraEscape(body).replaceAll('\r\n', '\n').replaceAll('\n', '<br>')}</p>\n<p>[/collapse]</p>';
}

String extraReference(String kind, int id) {
  if (!['poll', 'lottery'].contains(kind) || id <= 0) {
    throw const FormatException('引用编号无效');
  }
  return '[$kind id="$id"][/$kind]';
}

String extraRandomName() =>
    '[GalACG]EX${List.generate(9, (_) => Random.secure().nextInt(10)).join()}';
String extraWeb(String raw, {bool optional = false}) {
  final s = raw.trim();
  if (optional && s.isEmpty) return '';
  final u = Uri.tryParse(s);
  if (u == null ||
      !['http', 'https'].contains(u.scheme) ||
      u.host.isEmpty ||
      u.userInfo.isNotEmpty ||
      RegExp(r'["<>\r\n]').hasMatch(s)) {
    throw const FormatException('请输入完整 http/https 地址');
  }
  return s;
}

bool extraNamed(Json? account, String field, String name) =>
    account?[field] is List &&
    (account![field] as List).any(
      (v) => v is Map ? v['name'] == name : v == name,
    );
bool extraLotteryAllowed(Json? account) =>
    extraNamed(account, 'roles', 'administrator') ||
    extraNamed(account, 'roles', 'editor');
String _extraDate(dynamic raw) {
  final s = text(raw).trim();
  if (s.isEmpty) return '';
  if (!RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$').hasMatch(s)) {
    throw const FormatException('时间格式：yyyy-MM-dd HH:mm:ss');
  }
  final d = DateTime.tryParse(s);
  if (d == null ||
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}' !=
          s) {
    throw const FormatException('日期时间无效');
  }
  return s;
}

Json extraPollPayload(Json input) {
  final title = text(input['title']).trim();
  if (title.isEmpty || title.length > 1000) {
    throw const FormatException('投票主题需为 1～1000 个字符');
  }
  final source = rows(input['options']);
  if (source.length < 2) throw const FormatException('至少填写两个选项');
  final seen = <String>{};
  final images = input['image_mode'] == true,
      multi = input['multi_select'] == true;
  final opts = source.map((o) {
    final label = text(o['text']).trim();
    if (label.isEmpty || label.length > 255 || !seen.add(label)) {
      throw const FormatException('选项需为 1～255 个字符且不能重复');
    }
    return {
      ...o,
      'text': label,
      'image': extraWeb(text(o['image']), optional: !images),
    };
  }).toList();
  final max = multi ? int.tryParse(text(input['max_select'])) : 0;
  if (max == null || max < 0 || max > opts.length || (multi && max == 1)) {
    throw const FormatException('多选上限为 0（不限）或 2～选项数量');
  }
  final start = _extraDate(input['start_at']),
      end = _extraDate(input['end_at']);
  if (start.isNotEmpty && end.isNotEmpty && start.compareTo(end) >= 0) {
    throw const FormatException('截止时间必须晚于开始时间');
  }
  return {
    if (number(input['id']) > 0) 'id': number(input['id']),
    'title': title,
    'options': opts,
    'image_mode': images,
    'multi_select': multi,
    'max_select': max,
    'start_at': start.isEmpty ? null : start,
    'end_at': end.isEmpty ? null : end,
  };
}

String extraUpdateImage(
  String original, {
  required String src,
  required String alt,
  String width = '',
  String height = '',
  bool blur = false,
  String link = '',
}) {
  final root = html.parseFragment(original), image = root.querySelector('img');
  if (image == null) throw const FormatException('未找到图片');
  final nextSrc = extraWeb(src);
  if (nextSrc != image.attributes['src']) {
    for (final key in [
      'data-src',
      'data-original',
      'data-lazy-src',
      'srcset',
      'data-srcset',
    ]) {
      image.attributes.remove(key);
    }
  }
  image.attributes['src'] = nextSrc;
  image.attributes['style'] = _extraWithoutStyle(
    text(image.attributes['style']),
    {'width', 'height'},
  );
  image.attributes['alt'] = alt;
  for (final e in {'width': width, 'height': height}.entries) {
    final s = e.value.trim();
    if (s.isEmpty) {
      image.attributes.remove(e.key);
    } else {
      final size = _extraTableDimension(s);
      if (size.endsWith('%')) {
        image.attributes.remove(e.key);
        final style = text(image.attributes['style']);
        image.attributes['style'] =
            '$style${style.isEmpty || style.endsWith(';') ? '' : ';'}${e.key}:$size;';
      } else {
        image.attributes[e.key] = size.replaceAll('px', '');
      }
    }
  }

  if (blur) {
    image.classes.add('blur-img');
  } else {
    image.classes.remove('blur-img');
  }
  final href = extraWeb(link, optional: true), a = image.parent;
  if (a?.localName == 'a') {
    if (href.isEmpty) {
      final parent = a!.parentNode;
      final index = parent?.nodes.indexOf(a) ?? -1;
      if (parent != null && index >= 0) {
        parent.nodes.insertAll(index, a.nodes.toList());
        a.remove();
      }
    } else {
      a!.attributes['href'] = href;
    }
  } else if (href.isNotEmpty) {
    final anchor = html
        .parseFragment('<a href="${extraEscape(href)}"></a>')
        .querySelector('a')!;
    image.replaceWith(anchor);
    anchor.append(image);
  }
  final wrapper = dom.Element.tag('div')..nodes.addAll(root.nodes.toList());
  return wrapper.innerHtml;
}

String extraStyleValue(String style, String key) =>
    RegExp(
      '(?:^|;)\\s*${RegExp.escape(key)}\\s*:\\s*([^;]+)',
      caseSensitive: false,
    ).firstMatch(style)?.group(1)?.trim() ??
    '';
String _extraTableDimension(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return '';
  if (!RegExp(r'^[1-9][0-9]{0,3}(?:px|%)?$').hasMatch(s)) {
    throw const FormatException('表格宽高为像素或百分比，例如 600 或 100%');
  }
  if (s.endsWith('%') && int.parse(s.substring(0, s.length - 1)) > 100) {
    throw const FormatException('百分比不能大于 100');
  }
  return RegExp(r'^\d+$').hasMatch(s) ? '${s}px' : s;
}

String extraTable(
  String original, {
  required int rowCount,
  required int columnCount,
  required List<String> cells,
  String width = '',
  String height = '',
  String border = 'solid',
  String align = 'left',
}) {
  if (rowCount < 1 ||
      rowCount > 30 ||
      columnCount < 1 ||
      columnCount > 12 ||
      rowCount * columnCount > 180) {
    throw const FormatException('表格为 1～30 行、1～12 列，总计最多 180 格');
  }
  if (!['none', 'solid', 'dashed', 'dotted'].contains(border) ||
      !['left', 'center', 'right'].contains(align)) {
    throw const FormatException('表格样式无效');
  }
  final table =
      html.parseFragment(original).querySelector('table') ??
      dom.Element.tag('table');
  if (table.querySelector('table') != null) {
    throw const FormatException('嵌套表格请在源码模式编辑');
  }
  if (table.querySelector('[rowspan],[colspan]') != null) {
    throw const FormatException('此表格包含合并单元格，请在源码模式编辑以保留结构');
  }
  var style = _extraWithoutStyle(text(table.attributes['style']), {
    'width',
    'height',
    'border',
    'border-collapse',
    'text-align',
    'margin-left',
    'margin-right',
  });
  final w = _extraTableDimension(width), h = _extraTableDimension(height);
  style +=
      '${style.isEmpty || style.endsWith(';') ? '' : ';'}border-collapse:collapse;text-align:$align;border:${border == 'none' ? '0' : '1px $border #888'};';
  if (w.isNotEmpty) style += 'width:$w;';
  if (h.isNotEmpty) style += 'height:$h;';
  if (align == 'center') {
    style += 'margin-left:auto;margin-right:auto;';
  } else if (align == 'right') {
    style += 'margin-left:auto;margin-right:0;';
  }
  table.attributes.remove('width');
  table.attributes.remove('height');
  table.attributes['style'] = style;
  table.classes.remove('fr-dashed-borders');
  table.classes.remove('fr-dotted-borders');
  if (border == 'dashed') table.classes.add('fr-dashed-borders');
  if (border == 'dotted') table.classes.add('fr-dotted-borders');
  final existingRows = table.querySelectorAll('tr');
  final tbody = table.querySelector('tbody') ?? dom.Element.tag('tbody');
  if (tbody.parent == null) table.append(tbody);
  for (var i = existingRows.length - 1; i >= rowCount; i--) {
    existingRows[i].remove();
  }
  for (var i = 0; i < rowCount; i++) {
    final tr = i < existingRows.length
        ? existingRows[i]
        : dom.Element.tag('tr');
    if (tr.parent == null) tbody.append(tr);
    final prior = tr.children.toList();
    for (var j = prior.length - 1; j >= columnCount; j--) {
      prior[j].remove();
    }
    for (var j = 0; j < columnCount; j++) {
      final cell = j < prior.length ? prior[j] : dom.Element.tag('td');
      final value = i * columnCount + j < cells.length
          ? cells[i * columnCount + j]
          : '';
      if (j >= prior.length || cell.text != value) cell.text = value;
      if (cell.parent == null) tr.append(cell);
    }
  }
  return table.outerHtml;
}

String _extraWithoutStyle(String style, Set<String> names) => style
    .split(';')
    .where(
      (s) =>
          s.contains(':') &&
          !names.contains(s.split(':').first.trim().toLowerCase()),
    )
    .map((s) => s.trim())
    .join(';');
