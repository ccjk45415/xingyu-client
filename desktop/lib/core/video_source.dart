import 'dart:convert';

import 'package:html/parser.dart' as html;

import 'api.dart';
import 'source_document.dart';

bool directVideoUrl(String url) => RegExp(
  r'\.(mp4|m4v|webm|m3u8|mpd|mov)$',
  caseSensitive: false,
).hasMatch(Uri.tryParse(url)?.path ?? '');

/// Read public media attributes/JSON without evaluating page scripts.
String playableVideoFromHtml(String raw, Uri base) {
  final doc = html.parse(raw);
  final candidates = <String>[
    for (final e in doc.querySelectorAll(
      'video,video source,meta[property="og:video"],meta[property="og:video:url"],meta[property="og:video:secure_url"]',
    ))
      e.attributes['src'] ??
          e.attributes['data-src'] ??
          e.attributes['content'] ??
          '',
  ];
  void jsonUrls(dynamic value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if ([
              'src',
              'url',
              'contentUrl',
              'file',
              'video_url',
              'videoUrl',
              'mp4',
              'webm',
              'hls',
            ].contains(entry.key) &&
            entry.value is String) {
          candidates.add(entry.value as String);
        }
        if (entry.value is Map || entry.value is List) jsonUrls(entry.value);
      }
    } else if (value is List) {
      for (final item in value) {
        jsonUrls(item);
      }
    }
  }

  for (final e in doc.querySelectorAll(
    '[data-video], [data-setup], [data-sources], script[type="application/ld+json"], script[type="application/json"]',
  )) {
    for (final v in [
      e.attributes['data-video'],
      e.attributes['data-setup'],
      e.attributes['data-sources'],
      e.text,
    ]) {
      try {
        if (v != null) jsonUrls(jsonDecode(v));
      } catch (_) {
        /* Not JSON. */
      }
    }
  }
  for (final m in RegExp(
    r'''["'](?:src|file|contentUrl|video_url)["']\s*:\s*["']([^"']+)["']''',
  ).allMatches(raw)) {
    candidates.add(m[1]!.replaceAll(r'\/', '/').replaceAll(r'\u0026', '&'));
  }
  for (final candidate in candidates) {
    final url = sourceMediaUrl(candidate, base);
    if (url.isNotEmpty && directVideoUrl(url)) return url;
  }
  throw ApiFailure(422, '暂未读取到可播放的视频流，请重试；不会跳转外部浏览器');
}

class ArticleVideoSource {
  final List<String> urls;
  final Map<String, String> headers;
  const ArticleVideoSource(this.urls, this.headers);
  String get url => urls.first;
}

class BilibiliVideoRef {
  final String id;
  final bool av;
  final int page;
  const BilibiliVideoRef(this.id, {this.av = false, this.page = 1});
  static BilibiliVideoRef? parse(Uri uri) {
    if (![
      'www.bilibili.com',
      'bilibili.com',
      'm.bilibili.com',
      'player.bilibili.com',
    ].contains(uri.host)) {
      return null;
    }
    final match = RegExp(r'^/video/(BV[a-zA-Z0-9]{10}|av[0-9]+)(?:/|$)')
        .firstMatch(uri.path);
    final raw =
        match?[1] ??
        uri.queryParameters['bvid'] ??
        (uri.queryParameters['aid'] == null
            ? ''
            : 'av${uri.queryParameters['aid']}');
    if (!RegExp(r'^(?:BV[a-zA-Z0-9]{10}|av[0-9]+)$').hasMatch(raw)) return null;
    final page =
        int.tryParse(
          uri.queryParameters['p'] ?? uri.queryParameters['page'] ?? '1',
        ) ??
        1;
    return BilibiliVideoRef(
      raw.startsWith('av') ? raw.substring(2) : raw,
      av: raw.startsWith('av'),
      page: page.clamp(1, 2000),
    );
  }

  Map<String, String> get identity => {av ? 'aid' : 'bvid': id};
}

Map<String, String> articleVideoHeaders(String source) {
  final uri = Uri.tryParse(source);
  return {
    'Referer':
        uri?.scheme == 'https' && uri!.host.isNotEmpty && uri.userInfo.isEmpty
        ? '${uri.origin}/'
        : '$siteOrigin/',
    'User-Agent': 'Mozilla/5.0 Xingyu-Article-Video/1',
  };
}

List<String> bilibiliProgressiveUrls(Json response) {
  if (number(response['code']) != 0) {
    throw ApiFailure(422, '来源视频暂时无法公开播放，请稍后重试');
  }
  final parts = rows(object(response['data'])['durl']);
  if (parts.length != 1) throw ApiFailure(422, '来源没有提供可用的完整视频流，请稍后重试');
  final values = [
    text(parts.single['url']),
    ...((parts.single['backup_url'] as List?) ?? []).whereType<String>(),
  ];
  final result = <String>[];
  for (var value in values) {
    if (value.startsWith('//')) value = 'https:$value';
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort && uri.port != 443 ||
        !directVideoUrl(value)) {
      continue;
    }
    if (!result.contains(value)) result.add(value);
  }
  if (result.isEmpty) throw ApiFailure(422, '来源没有提供安全的视频播放地址');
  return result.take(3).toList();
}
