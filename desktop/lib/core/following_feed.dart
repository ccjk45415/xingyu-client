import 'api.dart';

typedef FeedGet = Future<Json> Function(String, [Map<String, dynamic>?]);
typedef FollowGet = Future<Json> Function(String);

/// Keep the current prefix in place and append unique, still-followed posts.
Json appendFollowingWindow(Json current, Json next) {
  final allowed = (next['ids'] as List? ?? []).map(number).toSet();
  final selected = number(next['selected']);
  final seen = <int>{};
  final posts = <Json>[];
  for (final post in [...rows(current['posts']), ...rows(next['posts'])]) {
    final author = number(post['user_id']) > 0
        ? number(post['user_id'])
        : number(object(post['user'])['id']);
    final id = number(post['id']);
    if (id > 0 &&
        allowed.contains(author) &&
        (selected == 0 || selected == author) &&
        seen.add(id)) {
      posts.add(post);
    }
  }
  return {...next, 'posts': posts};
}

class _CachedFeed {
  final Json data;
  final DateTime time;
  final bool complete;
  _CachedFeed(this.data, {this.complete = true}) : time = DateTime.now();
}

class _Timeline {
  final Json data;
  final double offset;
  final DateTime time = DateTime.now();
  _Timeline(this.data, this.offset);
}

/// Account-scoped, bounded memory cache. Each scan requests pages concurrently,
/// and publishes page one before waiting for the rest of the window.
class FollowingFeedStore {
  final FeedGet get;
  final FollowGet social;
  final bool Function() active;
  final _cache = <String, _CachedFeed>{};
  final _running = <String, Future<Json>>{};
  final _timelines = <int, _Timeline>{};
  Json? _follows;
  DateTime _followsAt = DateTime(2000);
  Future<Json>? _followsRequest;
  int _revision = 0;
  FollowingFeedStore({
    required this.get,
    required this.social,
    required this.active,
  });
  String _key(int author, int page) => '$author:$page';
  Json? cached(int author, int page) => _cache[_key(author, page)]?.data;
  Json? timeline(int author) => _timelines[author]?.data;
  double timelineOffset(int author) => _timelines[author]?.offset ?? 0;
  bool timelineFresh(int author) =>
      _timelines[author] != null &&
      DateTime.now().difference(_timelines[author]!.time).inSeconds < 60;
  void rememberTimeline(int author, Json data, double offset) {
    if (!active()) return;
    _timelines.remove(author);
    // Never truncate a cached prefix while keeping a cursor beyond that prefix.
    if (rows(data['posts']).length > 400) return;
    _timelines[author] = _Timeline(data, offset);
    while (_timelines.length > 6) {
      _timelines.remove(_timelines.keys.first);
    }
  }

  bool fresh(int author, int page) {
    final entry = _cache[_key(author, page)];
    return entry != null &&
        entry.complete &&
        DateTime.now().difference(entry.time).inSeconds < 60;
  }

  void clear() {
    _revision++;
    _cache.clear();
    _running.clear();
    _timelines.clear();
    _follows = null;
    _followsRequest = null;
    _followsAt = DateTime(2000);
  }

  void _check(int revision) {
    if (revision != _revision || !active()) throw ApiFailure(409, '账号或关注列表已变化');
  }

  Future<Json> _ids(int revision) async {
    if (_follows != null &&
        DateTime.now().difference(_followsAt).inSeconds < 60) {
      return _follows!;
    }
    final pending = _followsRequest ??= social('/dm/v1/follows/ids');
    try {
      final value = await pending;
      _check(revision);
      _follows = value;
      _followsAt = DateTime.now();
      return value;
    } finally {
      if (identical(_followsRequest, pending)) _followsRequest = null;
    }
  }

  Future<Json> load(int author, int page, {void Function(Json)? onPartial}) {
    final key = _key(author, page);
    final existing = _running[key];
    if (existing != null) return existing;
    final revision = _revision;
    late final Future<Json> pending;
    pending = _load(author, page, revision, onPartial)
        .then((value) {
          _check(revision);
          _cache.remove(key);
          _cache[key] = _CachedFeed(value);
          while (_cache.length > 12) {
            _cache.remove(_cache.keys.first);
          }
          return value;
        })
        .whenComplete(() {
          if (identical(_running[key], pending)) _running.remove(key);
        });
    _running[key] = pending;
    return pending;
  }

  Future<Json> _load(
    int author,
    int page,
    int revision,
    void Function(Json)? onPartial,
  ) async {
    final r = await _ids(revision);
    _check(revision);
    final ids = (r['ids'] as List? ?? []).map(number).toSet();
    if (ids.isEmpty) {
      return {
        ...r,
        'posts': <Json>[],
        'next_page': page,
        'has_more': false,
        'selected': 0,
      };
    }
    final selected = ids.contains(author) ? author : 0;
    Future<Json> fetch(int p) => get('post/list', {
      'page': p,
      'per_page': 24,
      'simple': 1,
      'include': 'user,categories:simple',
      'with[0]': 'user',
      'with[1]': 'categories',
      'order_by': 'created_at',
      'order': 'desc',
      if (selected > 0) 'user_id': selected,
    });
    final pages = <int, Json>{};
    Json snapshot(int end) {
      final posts = <Json>[], seen = <int>{};
      for (var p = page; p <= end; p++) {
        for (final post in rows(pages[p]?['data'])) {
          final id = number(post['user_id']) > 0
              ? number(post['user_id'])
              : number(object(post['user'])['id']);
          if (ids.contains(id) &&
              (selected == 0 || id == selected) &&
              number(post['id']) > 0 &&
              seen.add(number(post['id']))) {
            posts.add(post);
          }
        }
      }
      posts.sort(
        (a, b) => text(b['created_at']).compareTo(text(a['created_at'])),
      );
      final total = number(
        object(object(pages[page]?['meta'])['pagination'])['total_pages'],
      );
      return {
        ...r,
        'posts': posts,
        'next_page': end + 1,
        'has_more': end < total,
        'selected': selected,
      };
    }

    pages[page] = await fetch(page);
    _check(revision);
    var result = snapshot(page);
    _cache[_key(author, page)] = _CachedFeed(result, complete: false);
    while (_cache.length > 12) {
      _cache.remove(_cache.keys.first);
    }
    if (onPartial != null) onPartial(result);
    final total = number(
      object(object(pages[page]?['meta'])['pagination'])['total_pages'],
    );
    final remaining = selected > 0 ? 0 : (total - page).clamp(0, 2);
    if (remaining > 0) {
      await Future.wait([
        for (var i = 1; i <= remaining; i++)
          fetch(page + i).then((value) {
            _check(revision);
            pages[page + i] = value;
          }),
      ]);
      result = snapshot(page + remaining);
    }
    return result;
  }
}
