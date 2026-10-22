import 'dart:convert';

import 'package:html/parser.dart' as parser;

/// Source ranges allow URL-only edits to retain nested formatting and attributes.
class EditorLink {
  final int start, openEnd, closeStart, end;
  final String url, label;
  const EditorLink(
    this.start,
    this.openEnd,
    this.closeStart,
    this.end,
    this.url,
    this.label,
  );

  static EditorLink? at(String source, int a, int b) {
    final tokens = RegExp(
      r"""<!--[\s\S]*?-->|\[(dlbox|iframe|collapse|poll|lottery)\b[^\]]*\][\s\S]*?\[/\1\]|<(?:[^<>"']|"[^"]*"|'[^']*')*>""",
      caseSensitive: false,
    );
    final stack = <({int start, int end})>[];
    var literal = 0;
    final low = a < b ? a : b, high = a > b ? a : b;
    for (final token in tokens.allMatches(source)) {
      final raw = token.group(0)!;
      final tag = RegExp(r'^<(/?)\s*([a-zA-Z0-9]+)').firstMatch(raw);
      if (tag == null) continue;
      final name = tag.group(2)!.toLowerCase(),
          close = tag.group(1)!.isNotEmpty;
      if (name == 'pre' || name == 'code') {
        literal = (literal + (close ? -1 : 1)).clamp(0, 1000000);
        continue;
      }
      if (literal > 0 || name != 'a') continue;
      if (!close) {
        stack.add((start: token.start, end: token.end));
      } else if (stack.isNotEmpty) {
        final open = stack.removeLast();
        if (low >= open.start && high <= token.end) {
          final element = parser
              .parseFragment(source.substring(open.start, token.end))
              .querySelector('a');
          if (element?.querySelector('img') != null) return null;
          return EditorLink(
            open.start,
            open.end,
            token.start,
            token.end,
            element?.attributes['href'] ?? '',
            element?.text ?? '',
          );
        }
      }
    }
    return null;
  }

  String update(
    String source,
    String name,
    String href, {
    bool remove = false,
  }) {
    var inner = source.substring(openEnd, closeStart);
    if (remove) {
      return source.replaceRange(start, end, inner);
    }
    var opening = source.substring(start, openEnd);
    final attr = RegExp(
      r"""\s+href\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)""",
      caseSensitive: false,
    ).firstMatch(opening);
    final value = ' href="${const HtmlEscape().convert(href)}"';
    opening = attr == null
        ? '${opening.substring(0, opening.length - 1)}$value>'
        : opening.replaceRange(attr.start, attr.end, value);
    if (name != label) {
      inner = const HtmlEscape().convert(name).replaceAll('\n', '<br>');
    }
    return source.replaceRange(start, closeStart, '$opening$inner');
  }
}
