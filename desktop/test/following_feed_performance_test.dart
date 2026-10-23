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
