import '../ui/cached_image.dart';

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as parser;

import 'api.dart' show desktopVersion;
import 'platform.dart';
import 'html_cleanup.dart';

/// A native editable projection of the original HTML, not a HTML serializer.
/// Hidden tags, attributes, comments and opaque website components remain in
/// [source]. An edit changes only the source ranges the user actually selected.
class VisualHtmlController extends TextEditingController {
  String source = '';
  final List<_Atom> _atoms = [];
  bool _projecting = false;
  VoidCallback? onSourceChanged;
  void Function(String message)? onEditError;
  void Function(int start, int end, String markup)? onImageEdit;
  void Function(int start, int end, String markup)? onComponentEdit;

  void load(String html, {int? start, int? end}) {
    source = html;
    _projecting = true;
    _parse();
    final plain = _atoms.map((a) => a.text).join();
    super.value = TextEditingValue(
      text: plain,
      selection: TextSelection(
        baseOffset: start == null ? plain.length : visibleOffset(start),
        extentOffset: end == null ? plain.length : visibleOffset(end),
      ),
    );
    _projecting = false;
  }

  int sourceOffset(int position) {
    final p = position.clamp(0, text.length);
    if (_atoms.isEmpty) {
      final closing = RegExp(
        r'</(?:p|div)>\s*$',
        caseSensitive: false,
      ).firstMatch(source);
      return closing?.start ?? source.length;
    }
    var n = 0;
    for (final atom in _atoms) {
      if (p <= n) return atom.start;
      n += atom.text.length;
      if (p < n) return atom.start;
      if (p == n) return atom.end;
    }
    return _atoms.last.end;
  }

  int visibleOffset(int sourcePosition) {
    var n = 0;
    for (final atom in _atoms) {
      if (sourcePosition <= atom.start) return n;
      n += atom.text.length;
      if (sourcePosition < atom.end) return n;
    }
    return n;
  }

  @override
  set value(TextEditingValue next) {
    if (_projecting || next.text == text) {
      super.value = next;
      return;
    }
    final old = text;
    var a = 0;
    while (a < old.length && a < next.text.length && old[a] == next.text[a]) {
      a++;
    }
    var b = old.length, c = next.text.length;
    while (b > a && c > a && old[b - 1] == next.text[c - 1]) {
      b--;
      c--;
    }
    // An entity and a UTF-16 surrogate pair are indivisible source atoms. A
    // replacement that shares one code unit must still preserve the full glyph.
    var boundary = 0;
    for (final atom in _atoms) {
      final end = boundary + atom.text.length;
      if (a > boundary && a < end) a = boundary;
      if (b > boundary && b < end) {
        c += end - b;
        b = end;
      }
      boundary = end;
    }
    bool splitPair(String value, int at) =>
        at > 0 &&
        at < value.length &&
        value.codeUnitAt(at - 1) >= 0xd800 &&
        value.codeUnitAt(at - 1) <= 0xdbff &&
        value.codeUnitAt(at) >= 0xdc00 &&
        value.codeUnitAt(at) <= 0xdfff;
    if (splitPair(old, a)) a--;
    if (splitPair(old, b)) {
      b++;
      c++;
    }
    final inserted = next.text.substring(a, c);
    // Replacement characters are reserved for real, selected embedded widgets.
    // Pasted plain text cannot fabricate a component without source markup.
    final markup = const HtmlEscape()
        .convert(inserted.replaceAll('\uFFFC', ''))
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\n', '<br>');
    final removed = <({int a, int b})>[];
    var n = 0;
    for (final atom in _atoms) {
      final end = n + atom.text.length;
      if (n < b && end > a && atom.end > atom.start) {
        removed.add((a: atom.start, b: atom.end));
      }
      n = end;
    }
    final at = removed.isEmpty ? sourceOffset(a) : removed.first.a;
    var raw = source;
    for (final range in removed.reversed) {
      raw = raw.replaceRange(range.a, range.b, '');
    }
    raw = raw.replaceRange(at, at, markup);
    if (b > a) raw = removeEmptyEditingMarkup(raw);
    if (raw.length > 1000000) {
      onEditError?.call('正文请控制在100万字符以内，已保留修改前的内容');
      return;
    }
    // Keep IME's composing and selection in visible UTF-16 offsets. Projection
    // does not run an HTML formatter or rewrite untouched source bytes.
    source = raw;
    _parse();
    final projected = _atoms.map((a) => a.text).join();
    int clamp(int v) => v.clamp(0, projected.length);
    super.value = TextEditingValue(
      text: projected,
      selection: TextSelection(
        baseOffset: clamp(next.selection.baseOffset),
        extentOffset: clamp(next.selection.extentOffset),
      ),
      composing:
          next.composing.isValid && next.composing.end <= projected.length
          ? next.composing
          : TextRange.empty,
    );
    onSourceChanged?.call();
  }

  void _parse() {
    _atoms.clear();
    final tokens = RegExp(
      r'''\[(?:dlbox|iframe|collapse|poll|lottery)\b[^\]]*\][\s\S]*?\[/(?:dlbox|iframe|collapse|poll|lottery)\]|<(?:script|style|iframe|video|audio|svg|table)\b[^>]*>[\s\S]*?</(?:script|style|iframe|video|audio|svg|table)\s*>|<!--[\s\S]*?-->|<(?:[^<>"']|"[^"]*"|'[^']*')*>''',
      caseSensitive: false,
    );
    final stack = <({String tag, TextStyle style})>[];
    var style = const TextStyle();
    var offset = 0;
    void plain(int from, int to) {
      final value = source.substring(from, to);
      // Source indentation between block tags is not text content.
      if (value.trim().isEmpty &&
          value.contains('\n') &&
          !stack.any((v) => v.tag == 'pre' || v.tag == 'code')) {
        return;
      }
      for (final part in RegExp(
        r'&(?:#x[\da-fA-F]+|#\d+|\w+);|[\s\S]',
      ).allMatches(value)) {
        final raw = part.group(0)!;
        final decoded = raw.startsWith('&')
            ? (parser.parseFragment(raw).text ?? raw)
            : raw;
        _atoms.add(_Atom(decoded, from + part.start, from + part.end, style));
      }
    }

    for (final token in tokens.allMatches(source)) {
      plain(offset, token.start);
      final raw = token.group(0)!;
      offset = token.end;
      if (raw.startsWith('<!--')) continue;
      if (raw.startsWith('[') &&
          stack.any((v) => v.tag == 'pre' || v.tag == 'code')) {
        plain(token.start, token.end);
        continue;
      }
      if (raw.startsWith('[') ||
          RegExp(
            r'^<(script|style|iframe|video|audio|svg|table)\b',
            caseSensitive: false,
          ).hasMatch(raw)) {
        final label = raw.startsWith('[dlbox')
            ? '下载链接卡片'
            : raw.startsWith('[iframe')
            ? '外部链接'
            : raw.startsWith('<table')
            ? '表格 · 点击编辑'
            : '网站组件 · 原样保留';
        _atoms.add(
          _Atom('\uFFFC', token.start, token.end, style, label: label),
        );
        continue;
      }
      final tagMatch = RegExp(r'^<\s*(/?)\s*([\w:-]+)').firstMatch(raw);
      if (tagMatch == null) {
        _atoms.add(
          _Atom(
            '\uFFFC',
            token.start,
            token.end,
            style,
            label: 'HTML组件 · 原样保留',
          ),
        );
        continue;
      }
      final tag = tagMatch.group(2)!.toLowerCase();
      if (tagMatch.group(1) == '/') {
        final index = stack.lastIndexWhere((v) => v.tag == tag);
        if (index >= 0) {
          style = stack[index].style;
          stack.removeRange(index, stack.length);
        }
        if (const [
              'p',
              'div',
              'h1',
              'h2',
              'h3',
              'h4',
              'li',
              'blockquote',
              'pre',
            ].contains(tag) &&
            token.end < source.trimRight().length &&
            (_atoms.isEmpty || _atoms.last.text != '\n')) {
          // A paired boundary is a removable newline. Deleting it merges two
          // ordinary adjacent paragraphs, without leaving unmatched HTML tags.
          final next = RegExp(
            r'^\s*<(p|div)(?:\s[^>]*)?>',
            caseSensitive: false,
          ).firstMatch(source.substring(token.end));
          final merge =
              (tag == 'p' || tag == 'div') &&
              next?.group(1)?.toLowerCase() == tag;
          _atoms.add(
            _Atom(
              '\n',
              token.start,
              merge ? token.end + next!.end : token.start,
              style,
            ),
          );
        }
        continue;
      }
      final element = parser.parseFragment(raw).children.firstOrNull;
      if (tag == 'img') {
        final anchor = RegExp(
          r'''<a\b(?:[^<>"']|"[^"]*"|'[^']*')*>\s*$''',
          caseSensitive: false,
        ).firstMatch(source.substring(0, token.start));
        final close = RegExp(
          r'^\s*</a\s*>',
          caseSensitive: false,
        ).firstMatch(source.substring(token.end));
        _atoms.add(
          _Atom(
            '\uFFFC',
            anchor != null && close != null ? anchor.start : token.start,
            anchor != null && close != null ? token.end + close.end : token.end,
            style,
            image: element?.attributes['src'],
            label: element?.attributes['alt'] ?? '正文图片',
            blurred: element?.classes.contains('blur-img') ?? false,
          ),
        );
        continue;
      }
      if (tag == 'br' || tag == 'hr') {
        _atoms.add(
          _Atom(
            tag == 'br' ? '\n' : '\uFFFC',
            token.start,
            token.end,
            style,
            label: tag == 'hr' ? '────────────' : null,
          ),
        );
        continue;
      }
      stack.add((tag: tag, style: style));
      style = style.merge(_tagStyle(tag, element?.attributes['style'] ?? ''));
    }
    plain(offset, source.length);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final spans = <InlineSpan>[];
    final screenWidth = MediaQuery.sizeOf(context).width;
    final embedWidth = screenWidth < 700
        ? (screenWidth - 112).clamp(100.0, 280.0)
        : 280.0;
    final buffer = StringBuffer();
    TextStyle? runStyle;
    void flush() {
      if (buffer.isNotEmpty) {
        spans.add(TextSpan(text: buffer.toString(), style: runStyle));
        buffer.clear();
      }
    }

    for (final atom in _atoms) {
      if (atom.text == '\uFFFC') {
        flush();
        final uri = Uri.tryParse(atom.image ?? '');
        final validImage =
            uri != null &&
            ['http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty;
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: embedWidth + 6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
                child: validImage
                    ? GestureDetector(
                        onSecondaryTap: () => onImageEdit?.call(
                          atom.start,
                          atom.end,
                          source.substring(atom.start, atom.end),
                        ),
                        onLongPress: () => onImageEdit?.call(
                          atom.start,
                          atom.end,
                          source.substring(atom.start, atom.end),
                        ),
                        child: Tooltip(
                          message: isAndroid
                              ? '长按编辑图片 · 地址、说明、尺寸或移除'
                              : '右键编辑图片 · 地址、说明、尺寸或移除',
                          child: SizedBox(
                            width: embedWidth,
                            height: embedWidth * 180 / 280,
                            child: ImageFiltered(
                              imageFilter: ui.ImageFilter.blur(
                                sigmaX: atom.blurred ? 8 : 0,
                                sigmaY: atom.blurred ? 8 : 0,
                              ),
                              child: CachedImage(
                                atom.image!,
                                headers: const {
                                  'Referer': 'https://cangku.moe/',
                                  'User-Agent':
                                      'Mozilla/5.0 XingyuDesktop/$desktopVersion',
                                },
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => _card(
                                  '图片暂时无法加载 · 地址已保留',
                                  Icons.image_outlined,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                    : GestureDetector(
                        onTap: () => onComponentEdit?.call(
                          atom.start,
                          atom.end,
                          source.substring(atom.start, atom.end),
                        ),
                        child: Tooltip(
                          message: '点击编辑组件；选中后可删除',
                          child: _card(
                            atom.label ?? '网站组件',
                            Icons.widgets_outlined,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        );
      } else {
        if (runStyle != atom.style) flush();
        runStyle = atom.style;
        buffer.write(atom.text);
      }
    }
    flush();
    return TextSpan(style: style, children: spans);
  }
}

Widget _card(String label, IconData icon) => DecoratedBox(
  decoration: BoxDecoration(
    color: const Color(0xfff1ebfa),
    borderRadius: BorderRadius.circular(9),
  ),
  child: Padding(
    padding: const EdgeInsets.all(12),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 19, color: const Color(0xff8864ca)),
        const SizedBox(width: 9),
        Flexible(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    ),
  ),
);

TextStyle _tagStyle(String tag, String css) {
  var style = switch (tag) {
    'b' || 'strong' => const TextStyle(fontWeight: FontWeight.bold),
    'i' || 'em' => const TextStyle(fontStyle: FontStyle.italic),
    'u' => const TextStyle(decoration: TextDecoration.underline),
    's' ||
    'del' ||
    'strike' => const TextStyle(decoration: TextDecoration.lineThrough),
    'h1' => const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
    'h2' => const TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
    'h3' => const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
    'a' => const TextStyle(
      color: Color(0xff8864ca),
      decoration: TextDecoration.underline,
    ),
    'code' || 'pre' => const TextStyle(
      fontFamily: 'Consolas',
      backgroundColor: Color(0xfff1eff4),
    ),
    'blockquote' => const TextStyle(
      color: Color(0xff81738f),
      fontStyle: FontStyle.italic,
    ),
    'sup' || 'sub' => const TextStyle(fontSize: 11),
    _ => const TextStyle(),
  };
  for (final property in css.split(';')) {
    final colon = property.indexOf(':');
    if (colon < 0) continue;
    final key = property.substring(0, colon).trim().toLowerCase();
    final value = property.substring(colon + 1).trim();
    if (key == 'font-size') {
      final size = double.tryParse(value.replaceFirst(RegExp(r'px$'), ''));
      if (size != null) style = style.copyWith(fontSize: size.clamp(8, 72));
    }
    if (key == 'font-family') {
      final families = value
          .split(',')
          .map((s) => s.trim().replaceAll('"', '').replaceAll("'", ''))
          .where((s) => s.isNotEmpty)
          .toList();
      if (families.isNotEmpty) {
        style = style.copyWith(
          fontFamily: families.first,
          fontFamilyFallback: families.skip(1).toList(),
        );
      }
    }
    if (key == 'line-height') {
      final height = double.tryParse(value);
      if (height != null) style = style.copyWith(height: height.clamp(.8, 4));
    }
    if (key == 'color' || key == 'background-color') {
      var hex = value.replaceFirst('#', '');
      if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
      final n = int.tryParse(hex, radix: 16);
      if (hex.length == 6 && n != null) {
        style = key == 'color'
            ? style.copyWith(color: Color(0xff000000 | n))
            : style.copyWith(backgroundColor: Color(0xff000000 | n));
      }
    }
  }
  return style;
}

class _Atom {
  final String text;
  final int start, end;
  final TextStyle style;
  final String? image, label;
  final bool blurred;
  _Atom(
    this.text,
    this.start,
    this.end,
    this.style, {
    this.image,
    this.label,
    this.blurred = false,
  });
}
