import 'api.dart';

List<Json> categoryNodes(List<Json> tree) => [
  for (final node in tree) ...[node, ...categoryNodes(rows(node['children']))],
];
Set<int> categoryBranch(Json node) =>
    categoryNodes([node])
        .map((n) => number(n['id']))
        .where((id) => id > 0)
        .toSet();
Set<int> effectiveCategories(Set<int> selected, List<Json> tree) => selected
    .intersection(categoryNodes(tree).map((n) => number(n['id'])).toSet());
void toggleCategory(Set<int> selected, Json node, bool on, List<Json> tree) {
  final branch = categoryBranch(node);
  if (on) {
    selected.addAll(branch);
  } else {
    selected.removeAll(branch);
    // A selected parent would also include the unchecked child's posts.
    for (final parent in categoryNodes(tree)) {
      if (categoryBranch(parent).contains(number(node['id']))) {
        selected.remove(number(parent['id']));
      }
    }
  }
}

bool matchesCategories(Json post, Set<int> selected) =>
    rows(post['categories']).any((c) => selected.contains(number(c['id'])));
Json emptyPostPage(int page) => {
  'data': <Json>[],
  'meta': {
    'pagination': {'current_page': page, 'total_pages': 1, 'total': 0},
  },
};
