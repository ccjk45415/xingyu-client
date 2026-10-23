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
