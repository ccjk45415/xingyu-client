import 'dart:io';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as parser;

import 'api.dart';

Uri desktopSourceUri(Uri uri) {
  if (['www.dlsite.com', 'dlsite.com'].contains(uri.host)) {
    return uri.replace(
      path: uri.path.replaceFirstMapped(
        RegExp(r'^/(maniax|home|books|pro|soft)-touch/'),
        (m) => '/${m[1]}/',
      ),
    );
  }
  return uri;
}

String sourceImage(Element element, Uri base) {
  for (final key in [
    'data-src',
    'data-original',
    'data-lazy-src',
    'src',
    'data-srcset',
    'srcset',
  ]) {
    var raw = (element.attributes[key] ?? '').trim();
    if (raw.isEmpty) continue;
    if (key.endsWith('srcset')) {
      raw = raw.split(',').last.trim().split(RegExp(r'\s+')).first;
    }
    final uri = base.resolve(raw);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        !uri.host.contains('.') ||
        InternetAddress.tryParse(uri.host) != null ||
        RegExp(r'(^|\.)(local|internal|localhost|invalid|test)$')
            .hasMatch(uri.host) ||
        uri.hasPort && uri.port != 443 ||
        RegExp(r'(loading|blank|spacer)\.').hasMatch(uri.path.toLowerCase())) {
      continue;
    }
    return uri.toString();
  }
  return '';
}

List<Json> sourceTextBlocks(String value) => value
    .split(RegExp(r'\n\s*\n'))
    .where((s) => s.trim().isNotEmpty)
    .map((s) => <String, dynamic>{'kind': 'p', 'text': s})
    .toList();
String sourceBlockText(List<Json> blocks) => blocks
    .where((b) => b['kind'] != 'image')
    .map((b) => text(b['text']))
    .join('\n\n');
Json parseSourceDocument(String raw, Uri uri) {
  final doc = parser.parse(raw);
  final title =
      doc.querySelector('#work_name,h1')?.text ??
      doc.querySelector('meta[property="og:title"]')?.attributes['content'] ??
      doc.querySelector('title')?.text ??
      '';
  String cover = '';
  final candidate = doc
      .querySelector('meta[property="og:image"]')
      ?.attributes['content'];
  if (candidate != null) {
    final fake = Element.tag('img')..attributes['src'] = candidate;
    cover = sourceImage(fake, uri);
  }
  Element? intro;
  for (final css in [
    '.work_parts_container[itemprop="description"]',
    '.work_parts_container',
    '#work_description',
    '#game_area_description',
    '[itemprop="description"]',
    'article',
    'main',
  ]) {
    final e = doc.querySelector(css);
    if (e != null &&
        (e.text.trim().isNotEmpty || e.querySelector('img') != null)) {
      intro = e;
      break;
    }
  }
  final pageError = doc.querySelector('.error_box_work')?.text ?? '';
  if (intro == null &&
      RegExp(
        r'国|地域|country|region',
        caseSensitive: false,
      ).hasMatch(pageError)) {
    throw ApiFailure(422, '来源网站限制了当前网络出口地区，请检查代理出口或粘贴原文；未读取到详细介绍');
  }
  if (intro == null && ['www.dlsite.com', 'dlsite.com'].contains(uri.host)) {
    throw ApiFailure(422, '未读取到DLsite详细介绍，请重试或粘贴原文；不会用网页摘要代替');
  }
  intro ??= doc.body;
  if (intro == null) throw ApiFailure(422, '网页没有可读取的介绍');
  for (final e in intro.querySelectorAll(
    'script,style,nav,header,footer,noscript,iframe,form,button,svg',
  )) {
    e.remove();
  }
  final blocks = <Json>[];
  var buffer = StringBuffer();
  void flush(String kind) {
    final value = buffer
        .toString()
        .replaceAll(RegExp(r'[ \t\r\f]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .trim();
    buffer = StringBuffer();
    if (value.isNotEmpty) blocks.add({'kind': kind, 'text': value});
    if (blocks.length > 2000) throw ApiFailure(413, '介绍过长，未截断；请分次导入');
  }

  void walk(Node node, String kind) {
    if (node is Text) {
      buffer.write(node.data);
      return;
    }
    if (node is! Element) return;
    final tag = node.localName ?? '';
    if (tag == 'img') {
      flush(kind);
      final image = sourceImage(node, uri);
      if (image.isNotEmpty) {
        blocks.add({
          'kind': 'image',
          'url': image,
          'alt': node.attributes['alt'] ?? '',
        });
      }
      return;
    }
    if (tag == 'br') {
      buffer.write('\n');
      return;
    }
    final boundary = [
      'p',
      'div',
      'section',
      'article',
      'ul',
      'ol',
      'li',
      'blockquote',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'figure',
      'figcaption',
      'table',
      'tr',
    ].contains(tag);
    final next = RegExp(r'^h[1-6]$').hasMatch(tag)
        ? (['h1', 'h2'].contains(tag) ? 'h2' : 'h3')
        : tag == 'li'
        ? 'li'
        : tag == 'blockquote'
        ? 'quote'
        : kind;
    if (boundary) flush(kind);
    for (final child in node.nodes) {
      walk(child, next);
    }
    if (boundary) flush(next);
  }

  walk(intro, 'p');
  flush('p');
  if (blocks.isEmpty) throw ApiFailure(422, '未读取到作品详细介绍，请粘贴原文');
  return {
    'url': uri.toString(),
    'title': title.trim(),
    'cover': cover,
    'blocks': blocks,
    'text': sourceBlockText(blocks),
  };
}
