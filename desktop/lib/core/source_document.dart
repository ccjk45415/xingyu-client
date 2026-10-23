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

/// Only preserve public HTTPS media URLs; never execute page JavaScript.
String sourceMediaUrl(String raw, Uri base) {
  if (raw.trim().isEmpty) return '';
  final element = Element.tag('img')..attributes['src'] = raw.trim();
  return sourceImage(element, base);
}

Json? sourceVideo(Element element, Uri base) {
  final tag = element.localName;
  final candidates = <String>[
    element.attributes['data-src'] ?? '',
    element.attributes['src'] ?? '',
    element.attributes['data-mp4'] ?? '',
    element.attributes['data-webm'] ?? '',
    element.attributes['data-hls'] ?? '',
    for (final child in element.querySelectorAll('source'))
      child.attributes['src'] ?? child.attributes['data-src'] ?? '',
    if (tag == 'a') element.attributes['href'] ?? '',
  ];
  for (final raw in candidates) {
    final url = sourceMediaUrl(raw, base);
    if (url.isEmpty) continue;
    final host = Uri.parse(url).host;
    if (tag == 'a' &&
        !RegExp(
          r'\.(mp4|webm|m3u8|mpd)(?:[?#]|$)',
          caseSensitive: false,
        ).hasMatch(url) &&
        ![
          'chobit.cc',
          'www.youtube.com',
          'youtu.be',
          'www.bilibili.com',
        ].contains(host)) {
      continue;
    }
    return {
      'kind': 'video',
      'url': url,
      'embed': tag == 'iframe',
      'poster': sourceMediaUrl(
        element.attributes['poster'] ?? element.attributes['data-poster'] ?? '',
        base,
      ),
      'title': element.attributes['title'] ?? '作品视频',
      'source_url': base.toString(),
    };
  }
  return null;
}

/// Steam's appdetails response supplies metadata outside detailed_description.
Json parseSteamSource(Json data, Uri uri) {
  final source = parseSourceDocument(text(data['detailed_description']), uri);
  source['title'] = text(data['name']);
  source['cover'] = sourceMediaUrl(text(data['header_image']), uri);
  source['work_type'] = switch (text(data['type'])) {
    'game' || 'dlc' || 'demo' => 'game',
    'music' => 'music',
    'video' || 'episode' || 'series' => 'movie',
    'advertising' => 'other',
    'software' => 'software',
    _ => '',
  };
  String names(dynamic values) =>
      values is List ? values.whereType<String>().join(' / ') : '';
  final facts = <String>[
    text(source['facts']),
    if (names(data['developers']).isNotEmpty)
      'Developer：${names(data['developers'])}',
    if (names(data['publishers']).isNotEmpty)
      'Publisher：${names(data['publishers'])}',
    if (text(object(data['release_date'])['date']).isNotEmpty)
      'Release Date：${text(object(data['release_date'])['date'])}',
  ];
  source['facts'] = facts.where((v) => v.isNotEmpty).join('\n');
  final blocks = rows(source['blocks']);
  for (final movie in rows(data['movies'])) {
    final options = [
      object(movie['mp4'])['max'],
      object(movie['mp4'])['480'],
      object(movie['webm'])['max'],
      object(movie['webm'])['480'],
      movie['hls_h264'],
      movie['dash_h264'],
      movie['dash_av1'],
    ];
    final url = options
        .map((v) => sourceMediaUrl(text(v), uri))
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (url.isNotEmpty && !blocks.any((b) => b['url'] == url)) {
      blocks.add({
        'kind': 'video',
        'url': url,
        'embed': false,
        'poster': sourceMediaUrl(text(movie['thumbnail']), uri),
        'title': text(movie['name'], '作品视频'),
        'source_url': uri.toString(),
      });
    }
  }
  source['blocks'] = blocks;
  return source;
}

List<Json> sourceTextBlocks(String value) => value
    .split(RegExp(r'\n\s*\n'))
    .where((s) => s.trim().isNotEmpty)
    .map((s) => <String, dynamic>{'kind': 'p', 'text': s})
    .toList();
String sourceBlockText(List<Json> blocks) => blocks
    .where((b) => !['image', 'video'].contains(b['kind']))
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
  final facts = <String>[];
  for (final row in doc.querySelectorAll('tr')) {
    final cells = row.querySelectorAll('th,td');
    if (cells.length >= 2) {
      final label = cells.first.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final value = cells
          .skip(1)
          .map((c) => c.text.replaceAll(RegExp(r'\s+'), ' ').trim())
          .join(' / ');
      if (label.isNotEmpty &&
          label.length < 60 &&
          value.isNotEmpty &&
          value.length < 500) {
        facts.add('$label：$value');
      }
    }
  }
  for (final dt in doc.querySelectorAll('dt')) {
    final dd = dt.nextElementSibling;
    if (dd?.localName == 'dd' && dt.text.length < 60 && dd!.text.length < 500) {
      facts.add('${dt.text.trim()}：${dd.text.trim()}');
    }
  }
  for (final row in doc.querySelectorAll('.dev_row,.release_date')) {
    final label =
        row
            .querySelector('.subtitle,b')
            ?.text
            .replaceAll(RegExp(r'[:：]'), '')
            .trim() ??
        '';
    final value =
        row.querySelector('.summary,.date')?.text.trim() ??
        row.querySelectorAll('a').map((a) => a.text.trim()).join(' / ');
    if (label.isNotEmpty && value.isNotEmpty && value.length < 500) {
      facts.add('$label：$value');
    }
  }
  final maker = doc.querySelector('.maker_name')?.text.trim() ?? '';
  if (maker.isNotEmpty && maker.length < 200) facts.add('サークル名：$maker');
  Element? intro;
  // Some DLsite descriptions split text and trailers into sibling containers.
  if (['www.dlsite.com', 'dlsite.com'].contains(uri.host)) {
    final sections = doc.querySelectorAll('.work_parts_container').where((e) {
      var parent = e.parent;
      while (parent != null) {
        if (parent.classes.contains('work_parts_container')) return false;
        parent = parent.parent;
      }
      return true;
    }).toList();
    if (sections.length > 1) {
      intro = Element.tag('div');
      for (final section in sections) {
        intro.append(section.clone(true));
      }
    }
  }
  for (final css in [
    '.work_parts_container[itemprop="description"]',
    '.work_parts_container',
    '#work_description',
    '#game_area_description',
    '[itemprop="description"]',
    'article',
    'main',
  ]) {
    if (intro != null) break;
    final e = doc.querySelector(css);
    if (e != null &&
        (e.text.trim().isNotEmpty ||
            e.querySelector('img,video,iframe') != null)) {
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
    'script,style,nav,header,footer,noscript,form,button,svg',
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
    if (tag == 'video' ||
        tag == 'iframe' ||
        tag == 'a' ||
        node.attributes.containsKey('data-mp4') ||
        node.attributes.containsKey('data-webm')) {
      final video = sourceVideo(node, uri);
      if (video != null) {
        flush(kind);
        blocks.add(video);
        return;
      }
      if (tag == 'video' || tag == 'iframe') return;
    }
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
    'facts': facts.toSet().take(100).join('\n'),
    'work_type_codes': doc
        .querySelectorAll('#category_type a[href*="work_type/"]')
        .map(
          (a) =>
              RegExp(r'/work_type/([^/]+)')
                  .firstMatch(a.attributes['href'] ?? '')
                  ?.group(1) ??
              '',
        )
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList(),
    'cover': cover,
    'blocks': blocks,
    'text': sourceBlockText(blocks),
  };
}
