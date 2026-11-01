import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'category_preferences.dart';

/// Interest weights never leave this device; only normal category-list requests
/// are made to the website. A little exploration keeps the feed from narrowing.
Map<int, double> quickFeedInterests(List<Json> history, List<Json> tree) {
  final valid = categoryNodes(tree).map((c) => number(c['id'])).toSet();
  final weights = <int, double>{};
  for (var i = 0; i < history.length && i < 80; i++) {
    final ids = rows(history[i]['categories'])
        .map((c) => number(c['id']))
        .where((id) => id > 0 && (valid.isEmpty || valid.contains(id)))
        .toSet();
    for (final id in ids) {
      weights.update(
        id,
        (v) => v + 1 / (1 + i / 8),
        ifAbsent: () => 1 / (1 + i / 8),
      );
    }
  }
  return weights;
}

int quickFeedPages(Json result) {
  final meta = object(result['meta']),
      paging = object(object(result['meta'])['pagination']);
  for (final value in [
    paging['total_pages'],
    paging['last_page'],
    meta['last_page'],
    result['last_page'],
  ]) {
    if (number(value) > 0) return number(value);
  }
  final total = number(paging['total'] ?? meta['total']),
      per = number(paging['per_page'] ?? meta['per_page']);
  return total > 0 && per > 0 ? (total / per).ceil() : 1;
}

class QuickFeedStore extends ChangeNotifier {
  final Future<Json> Function(String, [Map<String, dynamic>?]) get;
  final List<Json> Function() history;
  final List<Json> Function() categories;
  final int Function() account;
  final Future<void> Function(int, List<Json>)? rememberCategories;
  final Random random;
  final List<Json> posts = [];
  final Map<int, Json> _enriched = {};
  final Set<int> _enrichmentAttempts = {};
  final Map<int, int> _pages = {};
  final Set<String> _requested = {};
  final Set<int> _seen = {};
  bool loading = false, refreshing = false, exhausted = false;
  String error = '';
  int _owner = 0, _epoch = 0;
  bool _disposed = false;

  QuickFeedStore({
    required this.get,
    required this.history,
    required this.categories,
    required this.account,
    this.rememberCategories,
    Random? random,
  }) : random = random ?? Random();

  Map<int, double> get interests => quickFeedInterests([
    for (final post in history()) _enriched[number(post['id'])] ?? post,
  ], categories());

  List<Json> get preferredCategories {
    final w = interests;
    final list = categoryNodes(categories())
        .where((c) => w.containsKey(number(c['id'])))
        .toList();
    list.sort((a, b) => w[number(b['id'])]!.compareTo(w[number(a['id'])]!));
    return list.take(3).toList();
  }

  void clear({bool notify = true}) {
    _epoch++;
    _owner = account();
    posts.clear();
    _enriched.clear();
    _enrichmentAttempts.clear();
    _pages.clear();
    _requested.clear();
    _seen.clear();
    loading = refreshing = exhausted = false;
    error = '';
    if (notify && !_disposed) notifyListeners();
  }

  bool _current(int epoch, int uid) =>
      !_disposed && epoch == _epoch && uid == account();

  Future<void> _enrich(int epoch, int uid) async {
    final missing = history()
        .where(
          (p) =>
              rows(p['categories']).isEmpty &&
              number(p['id']) > 0 &&
              !_enrichmentAttempts.contains(number(p['id'])),
        )
        .take(6);
    await Future.wait(
      missing.map((p) async {
        _enrichmentAttempts.add(number(p['id']));
        try {
          final result = await get('post/info', {
            'id': number(p['id']),
            'include': 'categories:simple',
            'exclude_view': 1,
          });
          if (_current(epoch, uid)) {
            _enriched[number(p['id'])] = {
              ...p,
              'categories': object(result['data'])['categories'],
            };
          }
        } catch (_) {
          // A missing old work must not prevent the recommendation feed loading.
        }
      }),
    );
    if (_current(epoch, uid)) {
      try {
        await rememberCategories?.call(uid, _enriched.values.toList());
      } catch (_) {}
      if (_current(epoch, uid)) notifyListeners();
    }
  }

  int _interestCategory(Map<int, double> weights) {
    if (weights.isEmpty) return 0;
    var target =
        random.nextDouble() * weights.values.fold<double>(0, (a, b) => a + b);
    for (final entry in weights.entries) {
      target -= entry.value;
      if (target <= 0) return entry.key;
    }
    return weights.keys.last;
  }

  int? _nextPage(int category) {
    final count = _pages[category];
    if (count == null) return _requested.contains('$category:1') ? null : 1;
    final start = random.nextInt(count) + 1;
    for (var i = 0; i < count; i++) {
      final page = (start - 1 + i) % count + 1;
      if (!_requested.contains('$category:$page')) return page;
    }
    return null;
  }

  Future<List<Json>> _sample(int category, int epoch, int uid) async {
    final page = _nextPage(category);
    if (page == null) return [];
    final key = '$category:$page';
    _requested.add(key);
    try {
      final result = await get('post/list', {
        'page': page,
        'per_page': 24,
        'simple': '1',
        'include': 'user,categories:simple',
        if (category > 0) 'category_in[0]': category,
      });
      if (!_current(epoch, uid)) return [];
      _pages[category] = quickFeedPages(result).clamp(1, 100000);
      return rows(result['data']);
    } catch (_) {
      if (_current(epoch, uid)) _requested.remove(key);
      rethrow;
    }
  }

  Future<void> load({bool refresh = false}) async {
    if (_owner != account()) clear(notify: false);
    if (_disposed || loading || account() <= 0 || (exhausted && !refresh)) {
      return;
    }
    final uid = account(), epoch = _epoch;
    loading = true;
    refreshing = refresh;
    error = '';
    if (refresh) {
      _requested.clear();
      // Keep the currently visible batch out of the next refresh, but permit a
      // previously exhausted small catalogue to be explored again.
      _seen
        ..clear()
        ..addAll(posts.map((p) => number(p['id'])));
    }
    notifyListeners();
    try {
      // Older history omitted categories. Fill it without delaying the first
      // visible batch behind unrelated historical-detail network requests.
      unawaited(_enrich(epoch, uid));
      final weights = interests, candidates = <int, Json>{};
      final read = history().map((p) => number(p['id'])).toSet();
      Object? failure;
      for (var round = 0; round < 3 && candidates.length < 18; round++) {
        final category = _interestCategory(weights);
        final results = await Future.wait([
          for (final id in {category, 0})
            _sample(id, epoch, uid).then<List<Json>?>(
              (v) => v,
              onError: (Object e) {
                failure = e;
                return null;
              },
            ),
        ]);
        if (!_current(epoch, uid)) return;
        for (final result in results) {
          for (final post in result ?? <Json>[]) {
            final id = number(post['id']);
            if (id <= 0 ||
                _seen.contains(id) ||
                read.contains(id) ||
                (post['status'] != null && post['status'] != 'publish')) {
              continue;
            }
            candidates[id] = post;
          }
        }
        if (results.every((result) => result == null)) break;
      }
      if (candidates.isEmpty && failure != null) throw failure!;
      final ranked = candidates.values.map((p) {
        final affinity = rows(p['categories'])
            .fold<double>(0, (sum, c) => sum + (weights[number(c['id'])] ?? 0));
        return (p, random.nextDouble() + (affinity > 0 ? .65 : 0));
      }).toList()..sort((a, b) => b.$2.compareTo(a.$2));
      final batch = ranked.take(24).map((p) => p.$1).toList()..shuffle(random);
      if (refresh && batch.isNotEmpty) posts.clear();
      posts.addAll(batch);
      _seen.addAll(batch.map((p) => number(p['id'])));
      if (_seen.length > 3000) {
        _seen.removeAll(_seen.take(_seen.length - 2000).toList());
      }
      exhausted = batch.isEmpty;
      if (batch.isEmpty && refresh) error = '暂时没有新的推荐，稍后再来换一批吧';
    } catch (_) {
      if (_current(epoch, uid)) error = '推荐暂时未能加载，请检查网络后重试';
    } finally {
      if (_current(epoch, uid)) {
        loading = refreshing = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }
}
