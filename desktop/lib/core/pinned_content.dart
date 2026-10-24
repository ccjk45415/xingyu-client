import 'api.dart';

bool isPinned(Json item) =>
    item['is_sticky'] == true ||
    item['is_sticky'] == 1 ||
    item['is_sticky'] == '1';

List<Json> pinnedFirst(List<Json> items) {
  final seen = <int>{}, pinned = <Json>[], regular = <Json>[];
  for (final item in items) {
    final id = number(item['id']);
    if (id > 0 && !seen.add(id)) continue;
    (isPinned(item) ? pinned : regular).add(item);
  }
  return [...pinned, ...regular];
}
