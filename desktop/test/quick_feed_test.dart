import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/quick_feed.dart';

class LastPageRandom implements Random {
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => .5;
  @override
  int nextInt(int max) => max - 1;
}

Json work(int id, {int category = 10, String status = 'publish'}) => {
  'id': id,
  'title': '合成作品 $id',
  'status': status,
  'categories': [
    {'id': category},
  ],
};

Json page(List<Json> data, {int pages = 1}) => {
  'data': data,
  'meta': {
    'pagination': {'total_pages': pages},
  },
};

const List<Json> tree = [
  {
    'id': 1,
    'name': '作品',
    'children': [
      {'id': 10, 'name': '游戏'},
      {'id': 20, 'name': '音声'},
      {'id': 30, 'name': '漫画'},
      {'id': 40, 'name': '动画'},
    ],
  },
];

void main() {
  test(
    'interest weights favor recent repeated categories and validate the tree',
    () {
      final history = <Json>[
        {
          'id': 1,
          'categories': [
            {'id': 10},
            {'id': 10},
            {'id': 999},
            {'id': 0},
          ],
        },
        work(2, category: 20),
        work(3),
        for (var i = 3; i < 80; i++) work(i + 1, category: 30),
        work(81, category: 40),
      ];
      final weights = quickFeedInterests(history, tree);
      expect(weights[10], closeTo(1 + 1 / 1.25, .000001));
      expect(weights[20], closeTo(1 / 1.125, .000001));
      expect(weights[30], greaterThan(weights[10]!));
      expect(weights.containsKey(999), false);
      expect(weights.containsKey(0), false);
      expect(weights.containsKey(40), false);
      // Missing category data should not prevent an otherwise known history ID
      // from contributing while the full category tree is loading.
      expect(quickFeedInterests([work(1, category: 999)], const [])[999], 1);
    },
  );

  test(
    'preferred category labels follow weighted history, with a top-three cap',
    () {
      final store = QuickFeedStore(
        get: (_, [_]) async => page([]),
        account: () => 47,
        categories: () => tree,
        history: () => [
          work(1),
          work(2),
          work(3, category: 20),
          work(4, category: 30),
          work(5, category: 40),
        ],
      );
      addTearDown(store.dispose);
      expect(store.preferredCategories.map((c) => c['id']), [10, 20, 30]);
    },
  );

  test('page metadata variants produce valid bounded sampling inputs', () {
    expect(quickFeedPages(page([], pages: 7)), 7);
    expect(
      quickFeedPages({
        'meta': {'last_page': 4},
      }),
      4,
    );
    expect(quickFeedPages({'last_page': 6}), 6);
    expect(
      quickFeedPages({
        'meta': {
          'pagination': {'total': 49, 'per_page': 24},
        },
      }),
      3,
    );
    expect(
      quickFeedPages({
        'meta': {
          'pagination': {'total_pages': 0},
        },
      }),
      1,
    );
  });

  test('samples random pages, filters history/private rows, and deduplicates batches', () async {
    final reads = <(int, int)>[];
    Future<Json> get(String path, [Map<String, dynamic>? params]) async {
      expect(path, 'post/list');
      final category = number(params?['category_in[0]']);
      final current = number(params?['page']);
      reads.add((category, current));
      expect(params?['per_page'], 24);
      final offset = (current - 1) * 100;
      return page([
        for (
          var i = category == 0 ? 17 : 1;
          i <= (category == 0 ? 40 : 24);
          i++
        )
          work(offset + i),
        work(0),
        work(offset + 999, status: 'draft'),
        work(offset + 998, status: 'pending'),
      ], pages: 5);
    }

    final store = QuickFeedStore(
      get: get,
      history: () => [work(1)],
      categories: () => tree,
      account: () => 47,
      random: LastPageRandom(),
    );
    addTearDown(store.dispose);
    await store.load();
    expect(reads, containsAll([(10, 1), (0, 1)]));
    expect(store.posts, hasLength(24));
    expect(store.posts.any((p) => p['id'] == 1 || p['id'] == 0), false);
    expect(store.posts.every((p) => p['status'] == 'publish'), true);
    final first = store.posts.map((p) => number(p['id'])).toSet();
    expect(first.length, store.posts.length);

    await store.load();
    expect(reads, containsAll([(10, 5), (0, 5)]));
    expect(reads.toSet().length, reads.length);
    expect(store.posts.length, 48);
    expect(store.posts.map((p) => number(p['id'])).toSet().length, 48);
    expect(store.posts.take(24).map((p) => number(p['id'])).toSet(), first);
    expect(store.loading, false);
    expect(store.error, isEmpty);
  });

  test(
    'refresh replaces a batch while excluding the currently visible works',
    () async {
      var generation = 0;
      final store = QuickFeedStore(
        get: (_, [_]) async => page([
          // The overlap must not re-enter a refreshed visible batch.
          work(100),
          for (var i = 1; i <= 24; i++) work(generation * 1000 + i),
        ]),
        history: () => [],
        categories: () => tree,
        account: () => 47,
        random: Random(4),
      );
      addTearDown(store.dispose);
      await store.load();
      final oldIds = store.posts.map((p) => number(p['id'])).toSet();
      generation++;
      await store.load(refresh: true);
      final refreshed = store.posts.map((p) => number(p['id'])).toSet();
      expect(refreshed, isNotEmpty);
      expect(refreshed.intersection(oldIds), isEmpty);
      expect(refreshed.length, store.posts.length);
      expect(store.refreshing, false);
      expect(store.error, isEmpty);
    },
  );

  test(
    'network failure preserves a visible batch and permits a refresh retry',
    () async {
      var fail = false, generation = 0;
      final store = QuickFeedStore(
        get: (_, [_]) async {
          if (fail) throw const SocketFailureForTest();
          return page([work(1 + generation * 100)]);
        },
        history: () => [],
        categories: () => tree,
        account: () => 47,
      );
      addTearDown(store.dispose);
      await store.load();
      expect(store.posts.single['id'], 1);
      fail = true;
      await store.load(refresh: true);
      expect(store.posts.single['id'], 1);
      expect(store.error, contains('检查网络'));
      expect(store.loading, false);
      expect(store.refreshing, false);

      fail = false;
      generation++;
      await store.load(refresh: true);
      expect(store.posts.single['id'], 101);
      expect(store.error, isEmpty);
    },
  );

  test(
    'an account change discards late samples from the previous account',
    () async {
      var account = 47, requests = 0;
      final pending = Completer<Json>();
      final store = QuickFeedStore(
        get: (_, [_]) {
          requests++;
          return requests == 1
              ? pending.future
              : Future.value(page([work(202)]));
        },
        history: () => [],
        categories: () => tree,
        account: () => account,
      );
      addTearDown(store.dispose);
      final previousLoad = store.load();
      await Future<void>.delayed(Duration.zero);
      expect(store.loading, true);
      account = 48;
      await store.load();
      expect(store.posts.single['id'], 202);
      pending.complete(page([work(101)]));
      await previousLoad;
      expect(store.posts.single['id'], 202);
      expect(store.loading, false);
      expect(store.error, isEmpty);
    },
  );

  test(
    'history enrichment is view-free and discarded after account changes',
    () async {
      var account = 47;
      final info = Completer<Json>();
      final store = QuickFeedStore(
        get: (path, [params]) async {
          if (path == 'post/info') {
            expect(params?['exclude_view'], 1);
            expect(params?['include'], 'categories:simple');
            return info.future;
          }
          return page([work(202, category: 20)]);
        },
        history: () => account == 47
            ? [
                {'id': 11},
              ]
            : [work(12, category: 20)],
        categories: () => tree,
        account: () => account,
      );
      addTearDown(store.dispose);
      final previousLoad = store.load();
      await Future<void>.delayed(Duration.zero);
      account = 48;
      await store.load();
      info.complete({'data': work(11)});
      await previousLoad;
      await Future<void>.delayed(Duration.zero);
      expect(store.interests.keys, [20]);
      expect(store.preferredCategories.single['id'], 20);
      expect(store.posts.single['id'], 202);
    },
  );

  test(
    'a pending history detail does not delay the visible first batch',
    () async {
      final detail = Completer<Json>();
      final remembered = <(int, List<Json>)>[];
      final store = QuickFeedStore(
        get: (path, [params]) {
          if (path == 'post/info') return detail.future;
          return Future.value(page([work(202)]));
        },
        history: () => [
          {'id': 11},
        ],
        categories: () => tree,
        account: () => 47,
        rememberCategories: (owner, posts) async =>
            remembered.add((owner, posts)),
      );
      addTearDown(store.dispose);
      await store.load().timeout(const Duration(seconds: 1));
      expect(detail.isCompleted, false);
      expect(store.posts.single['id'], 202);
      expect(store.loading, false);
      expect(store.interests, isEmpty);
      detail.complete({'data': work(11, category: 20)});
      await Future<void>.delayed(Duration.zero);
      expect(store.interests.keys, [20]);
      expect(remembered.single.$1, 47);
      expect(remembered.single.$2.single['id'], 11);
    },
  );

  test(
    'failed history enrichment is not retried in every appended batch',
    () async {
      var detailReads = 0, listReads = 0;
      final store = QuickFeedStore(
        get: (path, [params]) async {
          if (path == 'post/info') {
            detailReads++;
            throw const SocketFailureForTest();
          }
          return page([work(100 + ++listReads)], pages: 100);
        },
        history: () => [
          {'id': 11},
        ],
        categories: () => tree,
        account: () => 47,
      );
      addTearDown(store.dispose);
      await store.load();
      await store.load();
      await store.load(refresh: true);
      expect(detailReads, 1);
      expect(store.posts, isNotEmpty);
      expect(store.error, isEmpty);
    },
  );

  test('complete network failure stops after one sampling round', () async {
    var listReads = 0;
    final store = QuickFeedStore(
      get: (path, [params]) async {
        expect(path, 'post/list');
        listReads++;
        throw const SocketFailureForTest();
      },
      history: () => [work(11)],
      categories: () => tree,
      account: () => 47,
    );
    addTearDown(store.dispose);
    await store.load();
    // One preferred-category request plus one exploration request, without
    // repeated timeouts for the same pages in three sampling rounds.
    expect(listReads, 2);
    expect(store.posts, isEmpty);
    expect(store.error, contains('检查网络'));
    expect(store.loading, false);
  });

  test(
    'concurrent loads are coalesced and exhausted samples make no new calls',
    () async {
      var calls = 0;
      final pending = Completer<Json>();
      final store = QuickFeedStore(
        get: (_, [_]) {
          calls++;
          return pending.future;
        },
        history: () => [],
        categories: () => tree,
        account: () => 47,
      );
      addTearDown(store.dispose);
      final first = store.load();
      await Future<void>.delayed(Duration.zero);
      await store.load();
      expect(calls, 1);
      pending.complete(page([]));
      await first;
      expect(store.exhausted, true);
      await store.load();
      expect(calls, 1);
    },
  );
}

class SocketFailureForTest implements Exception {
  const SocketFailureForTest();
}
