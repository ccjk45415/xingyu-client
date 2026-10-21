import 'dart:convert';

import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart' as dom;

import 'reader.dart';

/// Export is a separate, sanitized view. The original editable HTML is untouched.
String printablePost(String title, String source) {
  final fragment = parser.parseFragment(
    ReaderDocument.parse(source, inlineResources: true).content,
  );
  const tags = {
    'p',
    'div',
    'span',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'br',
    'hr',
    'b',
    'strong',
    'i',
    'em',
    'u',
    's',
    'del',
    'strike',
    'a',
    'img',
    'pre',
    'code',
    'blockquote',
    'ul',
    'ol',
    'li',
    'table',
    'thead',
    'tbody',
    'tfoot',
    'tr',
    'th',
    'td',
    'sup',
    'sub',
    'details',
    'summary',
  };
  const styles = {
    'color',
    'background-color',
    'font-size',
    'font-weight',
    'font-style',
    'font-family',
    'text-align',
    'line-height',
    'text-decoration',
    'width',
    'height',
    'max-width',
    'border',
    'border-collapse',
    'padding',
    'margin',
  };
  void clean(dom.Node parent) {
    for (final node in parent.nodes.toList()) {
      if (node is dom.Comment) {
        node.remove();
        continue;
      }
      if (node is! dom.Element) continue;
      final tag = node.localName;
      if (!tags.contains(tag)) {
        node.remove();
        continue;
      }
      for (final key in node.attributes.keys.toList()) {
        final name = key.toString().toLowerCase(),
            value = node.attributes[key]!;
        if (name == 'style') {
          final safe = value
              .split(';')
              .where((part) {
                final colon = part.indexOf(':');
                if (colon < 0 ||
                    !styles.contains(
                      part.substring(0, colon).trim().toLowerCase(),
                    )) {
                  return false;
                }
                final val = part.substring(colon + 1);
                return !RegExp(
                  r'url\s*\(|expression|@|[<>\\]',
                  caseSensitive: false,
                ).hasMatch(val);
              })
              .join(';');
          node.attributes[key] = safe;
        } else if (name == 'src' || name == 'href') {
          final uri = Uri.tryParse(value);
          if (uri == null ||
              !['http', 'https'].contains(uri.scheme) ||
              uri.host.isEmpty ||
              uri.userInfo.isNotEmpty) {
            node.attributes.remove(key);
          }
        } else if (!{
          'alt',
          'title',
          'colspan',
          'rowspan',
          'width',
          'height',
          'border',
          'open',
        }.contains(name)) {
          node.attributes.remove(key);
        }
      }
      clean(node);
    }
  }

  clean(fragment);
  const escape = HtmlEscape();
  return '<!doctype html><html lang="zh-CN"><head><meta charset="UTF-8">'
      '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; img-src https: http:; style-src \'unsafe-inline\'; base-uri \'none\'; form-action \'none\'; frame-src \'none\'">'
      '<title>${escape.convert(title)}</title><style>body{max-width:980px;margin:32px auto;padding:24px;font:16px/1.8 sans-serif;color:#322c48}img{max-width:100%;height:auto}table{border-collapse:collapse}td,th{border:1px solid #ddd;padding:8px}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f5f2f9;padding:16px}a{color:#805dc0}@media print{body{margin:0;padding:0}img{break-inside:avoid}}</style>'
      '</head><body><h1>${escape.convert(title)}</h1>${fragment.outerHtml}</body></html>';
}
