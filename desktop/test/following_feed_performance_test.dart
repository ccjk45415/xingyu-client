import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/following_feed.dart';

Json response(int page) => {
  'data': [
    {
      'id': page,
      'user_id': 77,
      'title': '作品$page',
      'created_at': '2026-10-23T0$page:00:00Z',
    },
    {'id': 100 + page, 'user_id': 88, 'title': '未关注'},
  ],
  'meta': {
    'pagination': {'total_pages': 20},
  },
};

void main() {
  test('old pinned announcement is deferred until its publication window, never padded per author', () async {
    final announcement = {
      'id': 5,
      'user_id': 88,
      'is_sticky': true,
      'created_at': '2026-05-07T21:00:00+08:00',
    };
    final requests = <Map<String, dynamic>>[];
    final store = FollowingFeedStore(
      active: () => true,
      social: (_) async => {
        'ids': [77, 88],
      },
      get: (_, [params]) async {
        requests.add(params!);
        final page = number(params['page']);
        return {
          'data': [
            if (page == 1) announcement,
            {
              'id': 100 + page,
              'user_id': 77,
              'created_at': '2026-10-24T10:00:00Z',
            },
          ],
          'meta': {
            'pagination': {'total_pages': 9},
          },
        };
      },
    );
    final first = await store.load(0, 1);
    expect(rows(first['posts']).map((p) => p['user_id']).toSet(), {77});
    expect(rows(first['deferred_posts']).single['id'], 5);
    expect(requests.every((p) => p['sticky'] == '0'), true);
    final later = appendFollowingWindow(first, {
      'ids': [77, 88],
      'selected': 0,
      'chronology': 1,
      'has_more': true,
      'next_page': 7,
      'scan_floor': '2026-10-19T00:00:00Z',
      'posts': [announcement],
    });
    expect(rows(later['posts']).any((p) => p['id'] == 5), false);
    expect(rows(later['deferred_posts']).length, 1);
    final history = appendFollowingWindow(later, {
      'ids': [77, 88],
      'selected': 0,
      'chronology': 1,
      'has_more': true,
      'next_page': 10,
      'scan_floor': '2026-05-01T00:00:00Z',
      'posts': [announcement],
    });
    expect(rows(history['posts']).where((p) => p['id'] == 5).length, 1);
    expect(rows(history['posts']).last['id'], 5);
    expect(rows(history['deferred_posts']), isEmpty);
  });
  test(
    'old sticky posts cannot sit above newer posts appended from later pages',
    () {
      Json post(int id, String created, {bool sticky = false}) => {
        'id': id,
        'user_id': 77,
        'created_at': created,
        'is_sticky': sticky,
        'updated_at': '2026-10-24T14:05:00+08:00',
      };
      final merged = appendFollowingWindow(
        {
          'posts': [
            post(100, '2026-10-24T14:01:00+08:00'),
            post(5, '2026-05-07T21:00:00+08:00', sticky: true),
          ],
        },
        {
          'ids': [77],
          'selected': 0,
          'next_page': 7,
          'has_more': true,
          'posts': [
            post(90, '2026-10-19T00:28:00+08:00'),
            post(5, '2026-05-07T21:00:00+08:00', sticky: true),
          ],
        },
      );
      expect(rows(merged['posts']).map((p) => p['id']), [100, 90, 5]);
      expect(merged['next_page'], 7);
      expect(merged['has_more'], true);
      final next = appendFollowingWindow(merged, {
        'ids': [77],
        'selected': 0,
        'next_page': 10,
        'has_more': false,
        'posts': [post(80, '2026-09-01T10:00:00+08:00')],
      });
      expect(rows(next['posts']).map((p) => p['id']), [100, 90, 80, 5]);
    },
  );
  test('publication sorting compares actual instants, handles equal times and unknown dates', () {
    final posts = <Json>[
      {'id': 1, 'created_at': '2026-10-24T12:00:00+08:00'},
      {'id': 3, 'created_at': '2026-10-24T05:00:00Z'},
      {'id': 2, 'created_at': '2026-10-24T05:00:00Z'},
      {'id': 4, 'created_at': 'not a date'},
      {'id': 5},
    ];
    sortFollowingPosts(posts);
    expect(posts.map((p) => p['id']), [3, 2, 1, 4, 5]);
  });
  test('first paint precedes remaining pages, remaining scans run concurrently, cache and dedup', () async {
    final pending = <int, Completer<Json>>{};
    var idsCalls = 0;
    final store = FollowingFeedStore(
      active: () => true,
      social: (_) async {
        idsCalls++;
        return {
          'ids': [77],
          'authors': [],
        };
      },
      get: (_, [params]) {
        final page = number(params!['page']);
        pending[page] = Completer<Json>();
        return pending[page]!.future;
      },
    );
    Json? first;
    final future = store.load(0, 1, onPartial: (v) => first = v);
    await Future<void>.delayed(Duration.zero);
    expect(pending.keys, [1]);
    pending[1]!.complete(response(1));
    await Future<void>.delayed(Duration.zero);
    expect(rows(first!['posts']).map((p) => p['id']), [1]);
    expect(pending.keys.toSet(), {1, 2, 3});
    expect(store.cached(0, 1), first);
    expect(store.fresh(0, 1), false);
    expect(identical(store.load(0, 1), future), isTrue);
    pending[3]!.complete(response(3));
    pending[2]!.complete(response(2));
    final result = await future;
    expect(rows(result['posts']).map((p) => p['id']), [3, 2, 1]);
    expect(result['next_page'], 4);
    expect(result['has_more'], true);
    expect(store.fresh(0, 1), true);
    expect(idsCalls, 1);
    final selected = store.load(77, 1);
    await Future<void>.delayed(Duration.zero);
    pending[1]!.complete(response(1));
    await selected;
    expect(idsCalls, 1);
    store.clear();
    expect(store.cached(0, 1), isNull);
    expect(store.fresh(0, 1), false);
  });
  test(
    'logout/revision change rejects late results and never repopulates cache',
    () async {
      final pending = Completer<Json>();
      final store = FollowingFeedStore(
        active: () => true,
        social: (_) async => {
          'ids': [77],
        },
        get: (_, [params]) => pending.future,
      );
      final future = store.load(0, 1);
      final rejected = expectLater(future, throwsA(isA<ApiFailure>()));
      await Future<void>.delayed(Duration.zero);
      store.clear();
      pending.complete(response(1));
      await rejected;
      expect(store.cached(0, 1), isNull);
    },
  );
  test(
    'failure on later page retains first page with correct retry cursor',
    () async {
      final store = FollowingFeedStore(
        active: () => true,
        social: (_) async => {
          'ids': [77],
        },
        get: (_, [params]) async {
          if (params!['page'] == 2) throw ApiFailure(503, 'offline');
          return response(number(params['page']));
        },
      );
      await expectLater(store.load(0, 1), throwsA(isA<ApiFailure>()));
      final cached = store.cached(0, 1)!;
      expect(rows(cached['posts']).single['id'], 1);
      expect(cached['next_page'], 2);
    },
  );
  test('empty following does not request website pages', () async {
    final store = FollowingFeedStore(
      active: () => true,
      social: (_) async => {'ids': []},
      get: (_, [params]) async => throw StateError('must not fetch'),
    );
    final result = await store.load(0, 1);
    expect(rows(result['posts']), isEmpty);
    expect(result['has_more'], false);
  });
}
