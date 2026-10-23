import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/following_feed.dart';
import '../core/state.dart';
import '../ui/shared.dart';

int _n(dynamic value, [int fallback = 0]) {
  final n = number(value);
  return n > 0 ? n : fallback;
}

Future<bool> ensureSocialIdentity(BuildContext context) async {
  final app = stateOf(context), owner = stateOf(context).uid;
  if (app.verified) return true;
  if (!await confirm(
    context,
    '认证仓库账号',
    '关注、粉丝与动态使用星屿独立服务，手机和电脑共享。认证时临时将当前官网会话交给服务核验UID，不保存官网密码或会话；官网网页不会同步这些关注关系。',
    action: '认证并继续',
  )) {
    return false;
  }
  await app.enableIdentity();
  return context.mounted && app.uid == owner && app.verified;
}

class SocialGate extends StatelessWidget {
  final VoidCallback? refresh;
  const SocialGate({super.key, this.refresh});
  @override
  Widget build(BuildContext context) => Blank(
    '和喜欢的作者保持联系',
    '认证仓库账号后，在手机与电脑间同步关注关系和粉丝。动态展示关注作者的新投稿。',
    icon: Icons.people_alt_outlined,
    button: FilledButton.icon(
      onPressed: () => action(context, () async {
        if (await ensureSocialIdentity(context)) refresh?.call();
      }),
      icon: const Icon(Icons.verified_user_outlined),
      label: const Text('认证仓库账号'),
    ),
  );
}

class FollowButton extends StatefulWidget {
  final int id;
  final Json? author, initialStatus;
  const FollowButton(this.id, {super.key, this.author, this.initialStatus});
  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  AppState? app;
  bool following = false, mutual = false, busy = false, loaded = false;
  int request = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final value = stateOf(context);
    if (app == null) {
      app = value;
      if (widget.author != null) app!.authorCache[widget.id] = widget.author!;
      if (widget.initialStatus != null) {
        following = widget.initialStatus!['following'] == true;
        mutual = widget.initialStatus!['follows_you'] == true;
        loaded = true;
      } else {
        load();
      }
    }
  }

  Future<void> load() async {
    if (!app!.verified || widget.id == app!.uid) return;
    final owner = app!.uid, job = ++request;
    try {
      final r = await app!.social('/dm/v1/follows/status?peer=${widget.id}');
      if (mounted && app!.uid == owner && request == job) {
        setState(() {
          following = r['following'] == true;
          mutual = r['follows_you'] == true;
          loaded = true;
        });
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant FollowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialStatus != null &&
        widget.initialStatus != oldWidget.initialStatus) {
      following = widget.initialStatus!['following'] == true;
      mutual = widget.initialStatus!['follows_you'] == true;
      loaded = true;
    } else if (oldWidget.id != widget.id) {
      loaded = false;
      following = false;
      mutual = false;
      load();
    }
  }

  @override
  void dispose() {
    request++;
    super.dispose();
  }

  Future<void> toggle() async {
    if (busy) return;
    setState(() => busy = true);
    final owner = app!.uid;
    try {
      if (!await ensureSocialIdentity(context)) return;
      if (!mounted || app!.uid != owner) return;
      if (!loaded) {
        final r = await app!.social('/dm/v1/follows/status?peer=${widget.id}');
        following = r['following'] == true;
        mutual = r['follows_you'] == true;
      }
      if (!mounted || app!.uid != owner) return;
      if (following &&
          !await confirm(
            context,
            '取消关注？',
            '取消后，该作者的新投稿将不再出现在动态中。',
            action: '取消关注',
          )) {
        return;
      }
      final r = await app!.social(
        '/dm/v1/follows',
        body: {'peer_id': widget.id, 'following': !following},
      );
      if (mounted && app!.uid == owner) {
        setState(() {
          following = r['following'] == true;
          loaded = true;
        });
        app!.socialChanged();
      }
    } catch (e) {
      if (mounted) message(context, '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.id == stateOf(context).uid) return const SizedBox.shrink();
    return FilledButton.tonalIcon(
      onPressed: busy ? null : toggle,
      icon: Icon(
        following
            ? (mutual ? Icons.swap_horiz_rounded : Icons.check_rounded)
            : Icons.person_add_alt_1_rounded,
        size: 18,
      ),
      label: Text(
        busy
            ? '请稍候'
            : following
            ? (mutual ? '互相关注' : '已关注')
            : (mutual ? '回关' : '关注作者'),
      ),
    );
  }
}

class FollowStats extends StatelessWidget {
  const FollowStats({super.key});
  @override
  Widget build(BuildContext context) {
    final app = stateOf(context);
    Widget stats(Json data) => Surface(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          for (final e in [
            (
              '关注',
              'following',
              'following_count',
              Icons.person_add_alt_1_outlined,
            ),
            (
              '粉丝',
              'followers',
              'follower_count',
              Icons.favorite_border_rounded,
            ),
          ])
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => openRoute(
                  context,
                  DeskRoute('followPeople', e.$1, filter: e.$2),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Text(
                        app.verified ? '${_n(data[e.$3])}' : '—',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(e.$1, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (!app.verified) return stats({});
    return AsyncPane(
      refreshToken: '${app.uid}:${app.socialRevision}',
      load: () => app.social('/dm/v1/follows/status'),
      builder: (r, _) => stats(r),
    );
  }
}

class FollowPeoplePage extends StatelessWidget {
  final DeskRoute route;
  const FollowPeoplePage(this.route, {super.key});
  @override
  Widget build(BuildContext context) {
    final app = stateOf(context);
    if (!app.verified) return const SocialGate();
    final kind = route.filter == 'followers' ? 'followers' : 'following';
    return AsyncPane(
      refreshToken: '${app.uid}:${app.socialRevision}',
      load: () async {
        final owner = app.uid, generation = app.generation;
        final r = await app.social(
          '/dm/v1/follows?kind=$kind&page=${route.page}',
        );
        final users = rows(r['users']);
        // Canonical website profiles, including authors who have never installed the app.
        for (final u in users) {
          if (app.uid != owner || app.generation != generation) {
            throw ApiFailure(409, '账号已切换');
          }
          try {
            final id = _n(u['id']),
                p = object((await app.get('user/info', {'id': id}))['data']);
            if (app.uid == owner &&
                app.generation == generation &&
                _n(p['id']) == id) {
              app.authorCache[id] = p;
              final following = u['following'], followsYou = u['follows_you'];
              u.addAll(p);
              u['following'] = following;
              u['follows_you'] = followsYou;
            }
          } catch (_) {}
        }
        if (app.uid != owner || app.generation != generation) {
          throw ApiFailure(409, '账号已切换');
        }
        return {...r, 'users': users};
      },
      builder: (r, reload) => PageBody(
        width: 1000,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Heading(
              kind == 'followers' ? '我的粉丝' : '我的关注',
              '星屿独立关注 · 与手机端同步',
              trailing: IconButton(
                onPressed: reload,
                tooltip: '刷新列表',
                icon: const Icon(Icons.refresh),
              ),
            ),
            if (rows(r['users']).isEmpty)
              const Blank('这里还很安静', '到作者主页关注喜欢的创作者，让下一次更新不再错过。'),
            for (final user in rows(r['users']))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Surface(
                  padding: const EdgeInsets.all(14),
                  child: LayoutBuilder(
                    builder: (c, size) => Row(
                      children: [
                        Avatar(
                          user,
                          radius: 27,
                          onTap: () => openRoute(
                            context,
                            DeskRoute('author', '作者主页', id: _n(user['id'])),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: InkWell(
                            onTap: () => openRoute(
                              context,
                              DeskRoute('author', '作者主页', id: _n(user['id'])),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  text(user['nickname']),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  'UID ${_n(user['id'])}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                if (size.maxWidth > 500)
                                  Text(
                                    text(user['description']),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FollowButton(
                          _n(user['id']),
                          author: user,
                          initialStatus: user,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: route.page > 1
                      ? () => openRoute(context, route.at(route.page - 1))
                      : null,
                  child: const Text('上一页'),
                ),
                Text('${route.page} / ${_n(r['total_pages'], 1)}'),
                TextButton(
                  onPressed: route.page < _n(r['total_pages'], 1)
                      ? () => openRoute(context, route.at(route.page + 1))
                      : null,
                  child: const Text('下一页'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class FollowingFeedPage extends StatefulWidget {
  final DeskRoute route;
  const FollowingFeedPage(this.route, {super.key});
  @override
  State<FollowingFeedPage> createState() => _FollowingFeedPageState();
}

class _FollowingFeedPageState extends State<FollowingFeedPage> {
  AppState? app;
  String scope = '';
  Json? data;
  bool loading = false, loadingMore = false, fillQueued = false;
  Object? error, moreError;
  int job = 0, fillBudget = 2;
  double lastOffset = 0;
  double? restoreOffset;
  final scroll = ScrollController();
  DeskRoute get route => widget.route;
  String scopeOf(AppState current) =>
      '${current.uid}:${current.generation}:${current.socialRevision}:${current.verified}';
  @override
  void initState() {
    super.initState();
    scroll.addListener(onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = stateOf(context), key = scopeOf(stateOf(context));
    if (scope != key || app != current) {
      scope = key;
      app = current;
      reset();
    }
  }

  void reset() {
    job++;
    loading = false;
    loadingMore = false;
    error = null;
    moreError = null;
    fillBudget = 2;
    data =
        app!.followingFeed.timeline(route.id) ??
        app!.followingFeed.cached(route.id, 1);
    restoreOffset = app!.followingFeed.timelineOffset(route.id);
    lastOffset = restoreOffset!;
    if (app!.verified &&
        !(app!.followingFeed.timelineFresh(route.id) ||
            app!.followingFeed.timeline(route.id) == null &&
                app!.followingFeed.fresh(route.id, 1))) {
      scheduleMicrotask(reload);
    }
  }

  @override
  void didUpdateWidget(covariant FollowingFeedPage old) {
    super.didUpdateWidget(old);
    if (old.route.id != route.id) {
      remember(old.route.id);
      reset();
    }
  }

  bool active(int request) =>
      mounted && request == job && app!.verified && scope == scopeOf(app!);
  void remember([int? author]) {
    if (data != null &&
        app != null &&
        app!.verified &&
        scope == scopeOf(app!)) {
      app!.followingFeed.rememberTimeline(
        author ?? route.id,
        data!,
        scroll.hasClients ? scroll.offset : lastOffset,
      );
    }
  }

  @override
  void dispose() {
    remember();
    job++;
    scroll.dispose();
    super.dispose();
  }

  void cacheAuthors(Json result) {
    for (final post in rows(result['posts'])) {
      final author = object(post['user']);
      if (number(author['id']) > 0) {
        app!.authorCache[number(author['id'])] = author;
      }
    }
  }

  Future<void> reload({bool force = false}) async {
    if (!mounted || !app!.verified) return;
    final request = ++job;
    if (force) {
      app!.followingFeed.clear();
      app!.refreshBrowsing();
    }
    setState(() {
      loading = true;
      loadingMore = false;
      error = null;
      moreError = null;
      fillBudget = 2;
    });
    try {
      final result = await app!.followingFeed.load(
        route.id,
        1,
        onPartial: (value) {
          if (active(request) && data == null) setState(() => data = value);
        },
      );
      if (!active(request)) return;
      cacheAuthors(result);
      setState(() {
        data = result;
        restoreOffset = force
            ? 0
            : restoreOffset ?? (scroll.hasClients ? scroll.offset : lastOffset);
      });
      remember();
    } catch (e) {
      if (active(request)) setState(() => error = e);
    } finally {
      if (active(request)) setState(() => loading = false);
    }
  }

  Future<void> loadMore() async {
    if (data == null ||
        loading ||
        loadingMore ||
        data!['has_more'] != true ||
        !app!.verified) {
      return;
    }
    final request = job, nextPage = number(data!['next_page']);
    if (nextPage < 1) return;
    setState(() {
      loadingMore = true;
      moreError = null;
    });
    try {
      final next = await app!.followingFeed.load(route.id, nextPage);
      if (!active(request)) return;
      cacheAuthors(next);
      setState(() => data = appendFollowingWindow(data!, next));
      remember();
    } catch (e) {
      if (active(request)) setState(() => moreError = e);
    } finally {
      if (active(request)) setState(() => loadingMore = false);
    }
  }

  void onScroll() {
    if (scroll.hasClients) lastOffset = scroll.offset;
    if (scroll.hasClients &&
        scroll.position.pixels > 0 &&
        scroll.position.extentAfter < 420 &&
        moreError == null) {
      unawaited(loadMore());
    }
  }

  void queueFill() {
    if (fillQueued) return;
    fillQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fillQueued = false;
      if (!mounted || !scroll.hasClients) return;
      if (restoreOffset != null) {
        final offset = restoreOffset!;
        restoreOffset = null;
        scroll.jumpTo(offset.clamp(0, scroll.position.maxScrollExtent));
      }
      if (fillBudget > 0 &&
          !loading &&
          !loadingMore &&
          moreError == null &&
          rows(data?['posts']).isNotEmpty &&
          scroll.position.maxScrollExtent < 40) {
        fillBudget--;
        unawaited(loadMore());
      }
    });
  }

  Widget authors(BuildContext context, Json r) => Surface(
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '关注动态',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              ),
            ),
            IconButton(
              onPressed: loading ? null : () => reload(force: true),
              tooltip: '刷新动态',
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
            TextButton(
              onPressed: () => openRoute(
                context,
                const DeskRoute('followPeople', '我的关注', filter: 'following'),
              ),
              child: const Text('管理关注', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('全部动态'),
                selected: _n(r['selected']) == 0,
                onSelected: (_) =>
                    openRoute(context, const DeskRoute('followingFeed', '动态')),
              ),
              for (final author in rows(r['authors']))
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: InkWell(
                    onTap: () => openRoute(
                      context,
                      DeskRoute('followingFeed', '动态', id: _n(author['id'])),
                    ),
                    child: SizedBox(
                      width: 54,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: route.id == _n(author['id'])
                                    ? violet
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Avatar(
                              app!.authorCache[_n(author['id'])] ?? author,
                              radius: 20,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            text(
                              (app!.authorCache[_n(author['id'])] ??
                                  author)['nickname'],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget footer() {
    if (loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 17,
              height: 17,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text(
              '正在加载更多动态…',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    if (moreError != null) {
      return Center(
        child: TextButton.icon(
          onPressed: loadMore,
          icon: const Icon(Icons.refresh_rounded, size: 17),
          label: const Text('加载失败，点击重试'),
        ),
      );
    }
    final more = data?['has_more'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Text(
        loading
            ? '正在同步最新动态…'
            : more
            ? '上拉加载更多'
            : rows(data?['posts']).isEmpty
            ? '关注作者后，新投稿会出现在这里'
            : '已经到底啦',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
    );
  }

  Widget postCard(BuildContext context, Json post) {
    return Surface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Avatar(
                object(post['user']),
                radius: 19,
                onTap: () => openRoute(
                  context,
                  DeskRoute('author', '作者主页', id: _n(post['user_id'])),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text(object(post['user'])['nickname']),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${dateText(post['created_at'])} · 发布了新作品',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '作者主页',
                onPressed: () => openRoute(
                  context,
                  DeskRoute('author', '作者主页', id: _n(post['user_id'])),
                ),
                icon: const Icon(Icons.more_horiz),
              ),
            ],
          ),
          const SizedBox(height: 15),
          InkWell(
            onTap: () => openRoute(
              context,
              DeskRoute('article', '作品详情', id: _n(post['id'])),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  text(post['title']),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Cover(
                    text(post['thumb']),
                    height: MediaQuery.sizeOf(context).width < 700 ? 190 : 260,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${_n(post['view_count'])} 次浏览',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => openRoute(
                  context,
                  DeskRoute('article', '作品详情', id: _n(post['id'])),
                ),
                icon: const Icon(Icons.open_in_new, size: 17),
                label: const Text('查看作品'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!stateOf(context).verified) return const SocialGate();
    final r = data;
    if (r == null) {
      return error == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : Blank(
              '动态暂时未能加载',
              '请检查网络后重试。',
              button: FilledButton.icon(
                onPressed: () => reload(force: true),
                icon: const Icon(Icons.refresh),
                label: const Text('重新加载'),
              ),
            );
    }
    final posts = rows(r['posts']);
    queueFill();
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: NotificationListener<ScrollNotification>(
          onNotification: (event) {
            final positive =
                event is OverscrollNotification && event.overscroll > 0 ||
                event is ScrollUpdateNotification &&
                    (event.scrollDelta ?? 0) > 0;
            if (event.depth == 0 &&
                moreError == null &&
                positive &&
                event.metrics.extentAfter < 420) {
              fillBudget = 2;
              unawaited(loadMore());
            }
            return false;
          },
          child: RefreshIndicator(
            onRefresh: () => reload(force: true),
            child: Scrollbar(
              controller: scroll,
              child: CustomScrollView(
                key: const Key('following.timeline'),
                controller: scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        children: [
                          authors(context, r),
                          if (loading)
                            const LinearProgressIndicator(minHeight: 2),
                          if (error != null)
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    '刷新失败，当前动态已保留。',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => reload(force: true),
                                  child: const Text('重试'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (posts.isEmpty)
                    SliverToBoxAdapter(
                      child: Blank(
                        (r['ids'] as List? ?? []).isEmpty
                            ? '关注第一位作者'
                            : '近期暂未发现投稿',
                        (r['ids'] as List? ?? []).isEmpty
                            ? '从作者主页关注，之后来这里看新投稿。'
                            : '继续向上滑动，加载更早的动态。',
                        button: (r['ids'] as List? ?? []).isEmpty
                            ? FilledButton.icon(
                                onPressed: () => openRoute(
                                  context,
                                  const DeskRoute(
                                    'search',
                                    '搜索作者',
                                    filter: 'authors',
                                  ),
                                ),
                                icon: const Icon(Icons.person_search_outlined),
                                label: const Text('发现作者'),
                              )
                            : null,
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList.builder(
                      itemCount: posts.length,
                      itemBuilder: (c, i) => Padding(
                        key: ValueKey('following.post.${posts[i]['id']}'),
                        padding: const EdgeInsets.only(bottom: 12),
                        child: postCard(c, posts[i]),
                      ),
                      findChildIndexCallback: (key) {
                        if (key is! ValueKey<String>) return null;
                        final index = posts.indexWhere(
                          (p) => key.value == 'following.post.${p['id']}',
                        );
                        return index < 0 ? null : index;
                      },
                    ),
                  ),
                  SliverToBoxAdapter(child: footer()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthorFollowInfo extends StatelessWidget {
  final int id;
  const AuthorFollowInfo(this.id, {super.key});
  @override
  Widget build(BuildContext context) {
    final app = stateOf(context);
    if (!app.verified) return const SizedBox.shrink();
    return AsyncPane(
      refreshToken: '${app.uid}:${app.socialRevision}',
      load: () => app.social('/dm/v1/follows/status?peer=$id'),
      builder: (r, _) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          '星屿粉丝 ${_n(r['follower_count'])} · 星屿关注 ${_n(r['following_count'])}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ),
    );
  }
}
