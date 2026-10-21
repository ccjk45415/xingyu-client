import 'api.dart';

const defaultDiscovery = <String, dynamic>{
  'schema': 1,
  'revision': 0,
  'updated_at': null,
  'title': '今天，也有新的心动。',
  'content': '探索灵感 / 珍藏热爱 / 自在阅读',
};

bool _version(Json value) =>
    value['schema'] == 1 &&
    value['revision'] is int &&
    number(value['revision']) >= 0 &&
    (value['revision'] == 0 ||
        DateTime.tryParse(text(value['updated_at'])) != null);

bool _field(Object? value, int max) =>
    value is String &&
    value.trim().isNotEmpty &&
    value.runes.length <= max &&
    !RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]').hasMatch(value);

Json? validDiscovery(Object? value) {
  final data = object(value);
  return _version(data) &&
          _field(data['title'], 80) &&
          _field(data['content'], 1500)
      ? data
      : null;
}

Json? validAnnouncements(Object? value) {
  final data = object(value);
  if (!_version(data) || data['items'] is! List) return null;
  final items = rows(data['items']);
  if (items.length != (data['items'] as List).length || items.length > 10) {
    return null;
  }
  final seen = <String>{};
  for (final item in items) {
    final id = text(item['id']);
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(id) ||
        !seen.add(id) ||
        !_field(item['title'], 80) ||
        !_field(item['content'], 5000)) {
      return null;
    }
  }
  return data;
}
