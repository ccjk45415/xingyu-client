import 'package:flutter/material.dart';

import '../core/api.dart';
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

class FollowingFeedPage extends StatelessWidget {
  final DeskRoute route;
  const FollowingFeedPage(this.route, {super.key});
  Future<Json> load(AppState app) async {
    final owner = app.uid, generation = app.generation;
    final r = await app.social('/dm/v1/follows/ids'),
        ids = (r['ids'] as List? ?? []).map(number).toSet();
    if (ids.isEmpty) {
      return {...r, 'posts': <Json>[], 'next_page': 1, 'has_more': false};
    }
    final selected = ids.contains(route.id) ? route.id : 0;
    final posts = <Json>[], seen = <int>{};
    var next = route.page, more = true;
    for (var scan = 0; scan < (selected > 0 ? 1 : 3) && more; scan++) {
      if (app.uid != owner || app.generation != generation) {
        throw ApiFailure(409, '账号已切换');
      }
      final result = await app.get('post/list', {
        'page': next,
        'per_page': 24,
        'simple': 1,
        'include': 'user,categories:simple',
        'with[0]': 'user',
        'with[1]': 'categories',
        'order_by': 'created_at',
        'order': 'desc',
        if (selected > 0) 'user_id': selected,
      });
      if (app.uid != owner || app.generation != generation) {
        throw ApiFailure(409, '账号已切换');
      }
      for (final p in rows(result['data'])) {
        final author = object(p['user']),
            id = _n(p['user_id'], _n(author['id']));
        if (ids.contains(id) &&
            (selected == 0 || id == selected) &&
            seen.add(_n(p['id']))) {
          posts.add(p);
          if (author.isNotEmpty) app.authorCache[id] = author;
        }
      }
      more =
          next <
          _n(object(object(result['meta'])['pagination'])['total_pages'], next);
      next++;
    }
    posts.sort(
      (a, b) => text(b['created_at']).compareTo(text(a['created_at'])),
    );
    return {
      ...r,
      'posts': posts,
      'next_page': next,
      'has_more': more,
      'selected': selected,
    };
  }

  @override
  Widget build(BuildContext context) {
    final app = stateOf(context);
    if (!app.verified) return const SocialGate();
    return AsyncPane(
      refreshToken: '${app.uid}:${app.socialRevision}',
      load: () => load(app),
      builder: (r, reload) => PageBody(
        width: 1000,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Heading(
              '关注动态',
              '作者的新作品，与你的热爱保持同频。',
              trailing: IconButton(
                onPressed: reload,
                tooltip: '刷新动态',
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
            Surface(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.rss_feed_rounded, color: violet),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '只看关注的作者',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: () => openRoute(
                          context,
                          const DeskRoute(
                            'followPeople',
                            '我的关注',
                            filter: 'following',
                          ),
                        ),
                        child: const Text('管理关注'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: ChoiceChip(
                            label: const Text('全部动态'),
                            selected: _n(r['selected']) == 0,
                            onSelected: (_) => openRoute(
                              context,
                              const DeskRoute('followingFeed', '动态'),
                            ),
                          ),
                        ),
                        for (final a in rows(r['authors']))
                          Padding(
                            padding: const EdgeInsets.only(right: 14),
                            child: InkWell(
                              onTap: () => openRoute(
                                context,
                                DeskRoute(
                                  'followingFeed',
                                  '动态',
                                  id: _n(a['id']),
                                ),
                              ),
                              child: SizedBox(
                                width: 64,
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: route.id == _n(a['id'])
                                              ? violet
                                              : Colors.transparent,
                                          width: 2,
                                        ),
                                      ),
                                      child: Avatar(
                                        app.authorCache[_n(a['id'])] ?? a,
                                        radius: 23,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      text(
                                        (app.authorCache[_n(a['id'])] ??
                                            a)['nickname'],
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
            ),
            const SizedBox(height: 18),
            if ((r['ids'] as List? ?? []).isEmpty)
              Blank(
                '关注第一位作者',
                '从作者主页点击关注，之后来这里看他们的新投稿。',
                button: FilledButton.icon(
                  onPressed: () => openRoute(
                    context,
                    const DeskRoute('search', '搜索作者', filter: 'authors'),
                  ),
                  icon: const Icon(Icons.person_search_outlined),
                  label: const Text('发现作者'),
                ),
              )
            else if (rows(r['posts']).isEmpty)
              const Blank('这一段时间暂未发现投稿', '可以选择一位作者直接浏览，或继续向前查找。'),
            for (final post in rows(r['posts']))
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Surface(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Avatar(
                            object(post['user']),
                            radius: 23,
                            onTap: () => openRoute(
                              context,
                              DeskRoute(
                                'author',
                                '作者主页',
                                id: _n(post['user_id']),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  text(object(post['user'])['nickname']),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${dateText(post['created_at'])} · 发布了新作品',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '作者主页',
                            onPressed: () => openRoute(
                              context,
                              DeskRoute(
                                'author',
                                '作者主页',
                                id: _n(post['user_id']),
                              ),
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
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Cover(text(post['thumb']), height: 230),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            '${_n(post['view_count'])} 次浏览',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
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
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (route.page > 1)
                  TextButton(
                    onPressed: () => openRoute(
                      context,
                      DeskRoute('followingFeed', '动态', id: route.id),
                    ),
                    child: const Text('回到最新'),
                  ),
                if (r['has_more'] == true)
                  FilledButton.tonalIcon(
                    onPressed: () => openRoute(
                      context,
                      DeskRoute(
                        'followingFeed',
                        '动态',
                        id: route.id,
                        page: _n(r['next_page'], 1),
                      ),
                    ),
                    icon: const Icon(Icons.history_rounded),
                    label: const Text('继续查找更早动态'),
                  ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                '动态来自官网投稿；全部动态每次按时间检索最多3页，未找到时可继续向前查找。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          ],
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
