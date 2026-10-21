import 'dart:convert';

import 'package:html/parser.dart' as html;

import 'api.dart';

class ResourceBox {
  final String title, info, time, from;
  final Map<String, String> links;
  ResourceBox(
    this.title,
    this.info,
    this.links, {
    this.time = '',
    this.from = '',
  });
  String get details => [
    if (time.isNotEmpty) '上传时间：$time',
    if (from.isNotEmpty) '文件来源：$from',
    if (info.isNotEmpty) '文件信息：$info',
  ].join('\n');
}

class ReaderDocument {
  final String content;
  final List<ResourceBox> resources;
  ReaderDocument(this.content, this.resources);
  factory ReaderDocument.parse(String source, {bool inlineResources = false}) {
    final resources = <ResourceBox>[];
    final protected = <String>[];
    var marker = 'XINGYU_PROTECTED_CODE_';
    while (source.contains(marker)) {
      marker += '_';
    }
    // Shortcodes in an example code block are text, never live article components.
    final prepared = source.replaceAllMapped(
      RegExp(r'<pre\b[^>]*>[\s\S]*?</pre\s*>', caseSensitive: false),
      (m) {
        protected.add(m[0]!);
        return '$marker${protected.length - 1}_END';
      },
    );
    var result = prepared
        .replaceAllMapped(
          RegExp(
            r'\[dlbox\s*([^\]]*)\](?:[\s\S]*?\[/dlbox\])?',
            caseSensitive: false,
          ),
          (m) {
            final attrs = <String, String>{};
            final pattern = RegExp(
              "([a-zA-Z0-9_]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')",
            );
            for (final a in pattern.allMatches(m[1]!)) {
              attrs[a[1]!.toLowerCase()] =
                  html.parseFragment(a[2] ?? a[3] ?? '').text ?? '';
            }
            final links = <String, String>{};
            for (final e in attrs.entries.where(
              (e) => e.key.startsWith('link'),
            )) {
              final split = e.value.indexOf('|'),
                  name = split < 0 ? '打开资源' : e.value.substring(0, split),
                  url = (split < 0 ? e.value : e.value.substring(split + 1))
                      .trim();
              if (safeExternal(url)) {
                var label = name.isEmpty ? '打开资源' : name;
                var suffix = 2;
                while (links.containsKey(label)) {
                  label = '$name（${suffix++}）';
                }
                links[label] = url;
              }
            }
            final box = ResourceBox(
              attrs['title'] ?? '资源下载',
              attrs['info'] ?? '',
              links,
              time: attrs['time'] ?? '',
              from: attrs['from'] ?? '',
            );
            resources.add(box);
            if (inlineResources) {
              const e = HtmlEscape();
              return '<div class="xingyu-download"><h3>${e.convert(box.title)}</h3><p>上传时间：${e.convert(box.time.isEmpty ? '未知' : box.time)}<br>文件来源：${e.convert(box.from.isEmpty ? '未知' : box.from)}<br>文件信息：${e.convert(box.info.isEmpty ? '未知' : box.info)}</p><p>下载链接</p>${box.links.entries.map((l) => '<p><a href="${e.convert(l.value)}">${e.convert(l.key.isEmpty ? '打开资源' : l.key)}</a></p>').join()}</div>';
            }
            return '<p>◇ 资源 ${resources.length}</p>';
          },
        )
        .replaceAllMapped(
          RegExp(r'\[iframe\]([\s\S]*?)\[/iframe\]', caseSensitive: false),
          (m) {
            final url = html.parseFragment(m[1]!).text?.trim() ?? '';
            const e = HtmlEscape();
            return safeExternal(url) &&
                    ['http', 'https'].contains(Uri.tryParse(url)?.scheme)
                ? '<div class="xingyu-external"><p><strong>外部内容</strong></p><p><a href="${e.convert(url)}">${e.convert(url)}</a></p><p>在系统浏览器打开</p></div>'
                : '<p>外部链接无效</p>';
          },
        )
        .replaceAllMapped(
          RegExp(r'\[collapse\s*([^\]]*)\]', caseSensitive: false),
          (m) {
            final title = RegExp('title\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\')')
                .firstMatch(m[1]!);
            final label =
                html.parseFragment(title?[1] ?? title?[2] ?? '折叠内容').text ??
                '折叠内容';
            return '<details${RegExp(r'show\s*=\s*["\x27]true', caseSensitive: false).hasMatch(m[1]!) ? ' open' : ''}><summary>${const HtmlEscape().convert(label)}</summary>';
          },
        )
        .replaceAll(
          RegExp(r'\[/collapse\]', caseSensitive: false),
          '</details>',
        )
        .replaceAll(
          RegExp(r'\[/?code(?:\s[^\]]*)?\]', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(
            r'<(script|style|iframe|object|form)\b[^>]*>[\s\S]*?</\1\s*>',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'\[/?(?:spoiler|tip|warning|success|info|tabs|tab|quote|center|hide)(?:\s[^\]]*)?\]',
            caseSensitive: false,
          ),
          '<br>',
        );
    for (var i = 0; i < protected.length; i++) {
      result = result.replaceAll('$marker${i}_END', protected[i]);
    }
    return ReaderDocument(result, resources);
  }
}

Json rankParameters(String type, DateTime now) {
  final shanghai = now.toUtc().add(const Duration(hours: 8));
  final day = DateTime.utc(shanghai.year, shanghai.month, shanghai.day);
  final first = DateTime.utc(day.year);
  final ordinal = day.difference(first).inDays + 1;
  // Website dayjs: week begins Sunday, week containing Jan 1 is week 1.
  final start = first.subtract(Duration(days: first.weekday % 7));
  final next = DateTime.utc(day.year + 1);
  final nextStart = next.subtract(Duration(days: next.weekday % 7));
  final week = day.isBefore(nextStart)
      ? day.difference(start).inDays ~/ 7 + 1
      : 1;
  return {
    'year': day.year,
    'date_type': type,
    'date_value': type == 'daily'
        ? ordinal
        : type == 'weekly'
        ? week
        : day.month,
  };
}

String siteTimestamp(String raw) {
  if (raw.isEmpty) return '';
  if (!RegExp(r'(?:Z|[+-]\d{2}:\d{2})$').hasMatch(raw)) {
    return raw.replaceFirst('T', ' ').split('.').first;
  }
  final value = DateTime.tryParse(raw)?.toUtc().add(const Duration(hours: 8));
  if (value == null) return raw;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}
