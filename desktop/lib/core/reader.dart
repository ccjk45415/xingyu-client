import 'package:html/parser.dart' as html;
import 'api.dart';

class ResourceBox {
  final String title, info;
  final Map<String, String> links;
  ResourceBox(this.title, this.info, this.links);
}

class ReaderDocument {
  final String content;
  final List<ResourceBox> resources;
  ReaderDocument(this.content, this.resources);
  factory ReaderDocument.parse(String source) {
    final resources = <ResourceBox>[];
    final result = source
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
              if (safeExternal(url)) links[name] = url;
            }
            resources.add(
              ResourceBox(attrs['title'] ?? '资源下载', attrs['info'] ?? '', links),
            );
            return '<p>◇ 资源 ${resources.length}</p>';
          },
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
            r'\[/?(?:collapse|spoiler|tip|warning|success|info|tabs|tab|quote|center|hide)(?:\s[^\]]*)?\]',
            caseSensitive: false,
          ),
          '<br>',
        );
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
