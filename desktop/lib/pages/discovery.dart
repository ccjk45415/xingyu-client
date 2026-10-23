import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/category_preferences.dart';
import '../ui/category_filter.dart';
import '../core/home_content.dart';
import '../core/reader.dart';
import '../core/state.dart';
import '../ui/shared.dart';

class PostListPage extends StatelessWidget {
  final DeskRoute route;
  const PostListPage(this.route, {super.key});
  Future<Json> _load(AppState app) async {
    if (route.kind == 'search' && route.filter == 'authors') {
      return app.get('user/list', {
        'search': route.query,
        'page': route.page,
        'per_page': 20,
      });
    }
    final params = <String, dynamic>{
      'page': route.page,
      'per_page': 24,
      'simple': '1',
      'include': 'user,categories:simple',
      'with[0]': 'user',
      'with[1]': 'categories',
    };
    String endpoint = 'post/list';
    if (route.kind == 'search') {
      endpoint = 'post/search';
      params['search'] = route.query;
    }
    if (route.kind == 'rank') {
      endpoint = 'post/rank';
      params.addAll(
        rankParameters(
          route.filter.isEmpty ? 'daily' : route.filter,
          DateTime.now(),
        ),
      );
    }
    if (route.kind == 'favorites') {
      endpoint = 'user/favoritePost';
      params['id'] = app.uid;
    }
    if (route.kind == 'authorPosts') {
      endpoint = 'user/post';
      params['id'] = route.id;
    }
    if (route.kind == 'posts' && route.id > 0) {
      params['category_in[0]'] = route.id;
    }
    if (route.kind == 'home' && app.homeCategories != null) {
      if (app.categories.isEmpty) await app.loadCategories();
      final ids = effectiveCategories(app.homeCategories!, app.categories);
      if (ids.isEmpty) return emptyPostPage(route.page);
      var i = 0;
      for (final id in ids) {
        params['category_in[${i++}]'] = id;
      }
      final result = await app.get(endpoint, params);
      return {
        ...result,
        'data': rows(result['data'])
            .where((p) => matchesCategories(p, ids))
            .toList(),
      };
    }
    return app.get(endpoint, params);
  }

  @override
  Widget build(BuildContext context) {
    if (route.kind == 'search') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
            child: Wrap(
              spacing: 12,
              children: [
                for (final option in {'': '作品', 'authors': '作者'}.entries)
                  ChoiceChip(
                    label: Text(option.value),
                    selected: route.filter == option.key,
                    onSelected: (_) => openRoute(
                      context,
                      DeskRoute(
                        'search',
                        '搜索',
                        query: route.query,
                        filter: option.key,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _results(context)),
        ],
      );
    }
    return _results(context);
  }

  Widget _results(BuildContext context) {
    final app = stateOf(context);
    final authors = route.kind == 'search' && route.filter == 'authors';
    return AsyncPane(
      cacheKey:
          const {
            'home',
            'posts',
            'rank',
            'search',
            'authorPosts',
          }.contains(route.kind)
          ? 'list:${route.key}:${route.kind == 'home' ? app.homeFilterKey : ''}'
          : null,
      refreshToken: route.kind == 'home'
          ? '${app.homeFilterKey}:${app.categories.length}'
          : null,
      load: () => _load(app),
      builder: (data, reload) {
        final posts = rows(data['data']);
        return PageBody(
          key: PageStorageKey(
            'list:${route.key}:${route.kind == 'home' ? app.homeFilterKey : ''}',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (route.kind == 'home') ...[
                const HomeBanner(),
                const SizedBox(height: 20),
                const HomeFilterBar(),
              ],
              Heading(
                route.kind == 'home' ? '发现新的心动' : route.title,
                route.kind == 'search'
                    ? '“${route.query}”的搜索结果'
                    : route.kind == 'home'
                    ? '把值得珍藏的作品，留在你的宇宙里。'
                    : '封面、故事与灵感，都在这里。',
                trailing: IconButton(
                  onPressed: reload,
                  tooltip: '刷新作品',
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
              if (route.kind == 'rank')
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Wrap(
                    spacing: 12,
                    children: [
                      for (final e in {
                        'daily': '今日排行',
                        'weekly': '本周排行',
                        'monthly': '本月排行',
                      }.entries)
                        ChoiceChip(
                          label: Text(e.value),
                          selected:
                              (route.filter.isEmpty ? 'daily' : route.filter) ==
                              e.key,
                          onSelected: (_) => openRoute(
                            context,
                            DeskRoute('rank', '人气排行', filter: e.key),
                          ),
                        ),
                    ],
                  ),
                ),
              if (posts.isEmpty)
                Blank(authors ? '没有找到作者' : '这里还很安静', '试试其他分类或关键词吧。'),
              if (authors) ...[
                for (final person in posts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Surface(
                      padding: const EdgeInsets.all(8),
                      child: ListTile(
                        leading: Avatar(person, radius: 25),
                        title: Text(text(person['nickname'])),
                        subtitle: Text(
                          'UID ${number(person['id'])} · ${number(person['post_count'])} 篇投稿',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => openRoute(
                          context,
                          DeskRoute('author', '作者主页', id: number(person['id'])),
                        ),
                      ),
                    ),
                  ),
              ] else
                PostGrid(posts),
              Pagination(
                data,
                route.page,
                (page) => openRoute(context, route.at(page)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class PostGrid extends StatelessWidget {
  final List<Json> posts;
  const PostGrid(this.posts, {super.key});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (c, constraints) {
      final compact = constraints.maxWidth < 600;
      final columns = compact && constraints.maxWidth >= 300
          ? 2
          : (constraints.maxWidth / 248).floor().clamp(1, 6);
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: posts.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: compact ? 12 : 22,
          crossAxisSpacing: compact ? 12 : 22,
          mainAxisExtent: 280,
        ),
        itemBuilder: (c, index) => PostCard(posts[index], rank: index + 1),
      );
    },
  );
}

class PostCard extends StatefulWidget {
  final Json post;
  final int rank;
  const PostCard(this.post, {super.key, this.rank = 0});
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.post, author = object(p['user']);
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        transform: Matrix4.translationValues(0, hover ? -4 : 0, 0),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: violet.withValues(alpha: hover ? .12 : .035),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => openRoute(
              context,
              DeskRoute('article', '作品详情', id: number(p['id'])),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).width < 700 ? 145 : 156,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Cover(text(p['thumb'])),
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .45),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            rows(p['categories']).isNotEmpty
                                ? text(rows(p['categories']).first['name'])
                                : '星屿精选',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 13, 16, 0),
                  child: Text(
                    text(p['title'], '未命名作品'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      height: 1.55,
                      fontSize: 14,
                    ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 15),
                  child: Row(
                    children: [
                      Avatar(author, radius: 11),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          text(author['nickname'], '仓库用户'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      if (MediaQuery.sizeOf(context).width >= 700)
                        const Icon(
                          Icons.visibility_outlined,
                          size: 13,
                          color: Colors.grey,
                        ),
                      if (MediaQuery.sizeOf(context).width >= 700)
                        const SizedBox(width: 4),
                      if (MediaQuery.sizeOf(context).width >= 700)
                        Text(
                          '${number(p['view_count'])}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CategoryPage extends StatelessWidget {
  const CategoryPage({super.key});
  @override
  Widget build(BuildContext context) => stateOf(context).categoryTopNavigation
      ? const CategoryTabsPage()
      : AsyncPane(
          cacheKey: 'category-grid',
          load: () =>
              stateOf(context).get('category/list', {'all': 1, 'type': 'post'}),
          builder: (data, reload) => PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Heading(
                  '按兴趣漫游',
                  '从喜欢的分类出发，寻找下一份心动。',
                  trailing: IconButton(
                    tooltip: '刷新内容',
                    onPressed: reload,
                    icon: const Icon(Icons.refresh),
                  ),
                ),
                for (final category in rows(data['data']))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.interests_outlined,
                                color: violet,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  text(category['name']),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                              TextButton(
                                onPressed: () => openRoute(
                                  context,
                                  DeskRoute(
                                    'posts',
                                    text(category['name']),
                                    id: number(category['id']),
                                  ),
                                ),
                                child: const Text('浏览全部  →'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final sub in rows(category['children']))
                                ActionChip(
                                  label: Text(text(sub['name'])),
                                  onPressed: () => openRoute(
                                    context,
                                    DeskRoute(
                                      'posts',
                                      text(sub['name']),
                                      id: number(sub['id']),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
}

class HomeBanner extends StatefulWidget {
  const HomeBanner({super.key});
  @override
  State<HomeBanner> createState() => _HomeBannerState();
}

class _HomeBannerState extends State<HomeBanner> with WidgetsBindingObserver {
  final controller = PageController();
  Timer? rotation, heartbeat, retry;
  WebSocket? socket;
  SocketConnector? connector;
  Json board = {'schema': 1, 'revision': 0, 'updated_at': null, 'items': []};
  Json discovery = Map.of(defaultDiscovery);
  List<Json> get notices => rows(board['items']);
  bool online = false, active = true;
  int page = 0, generation = 0;
  DateTime touched = DateTime(2000);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    rotation = Timer.periodic(const Duration(seconds: 6), (_) {
      if (active &&
          controller.hasClients &&
          DateTime.now().difference(touched).inSeconds > 10) {
        controller.animateToPage(
          1 - page,
          duration: const Duration(milliseconds: 550),
          curve: Curves.easeInOutCubic,
        );
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final local = stateOf(context).local;
      board = validAnnouncements(local['announcements']) ?? board;
      discovery = validDiscovery(local['discovery']) ?? discovery;
      setState(() {});
      unawaited(connect());
    });
  }

  void stop() {
    connector?.cancel();
    generation++;
    heartbeat?.cancel();
    retry?.cancel();
    final old = socket;
    socket = null;
    if (old != null) unawaited(old.close());
  }

  void accept(Object? raw, int current, {bool live = true}) {
    if (!mounted || !active || current != generation) return;
    final data = validAnnouncements(raw);
    if (data == null) return;
    final next = validDiscovery(data['discovery']);
    setState(() {
      if (number(data['revision']) >= number(board['revision'])) board = data;
      if (next != null &&
          number(next['revision']) >= number(discovery['revision'])) {
        discovery = next;
      }
      online = live;
    });
    final app = stateOf(context);
    app.local['announcements'] = board;
    app.local['discovery'] = discovery;
    unawaited(app.persist().catchError((_) {}));
  }

  Future<void> connect() async {
    stop();
    final current = generation;
    if (!active) return;
    final wire = connector ??= stateOf(context).socketFactory();
    try {
      final origin = stateOf(context).service.origin
          .replaceFirst('https:', 'wss:')
          .replaceFirst('http:', 'ws:');
      final ws = await wire.connect('$origin/announcements/live');
      if (!mounted || !active || current != generation) {
        unawaited(ws.close());
        return;
      }
      socket = ws;
      ws.listen(
        (raw) {
          if (!mounted || current != generation || raw == 'pong') return;
          try {
            final event = object(jsonDecode(raw as String));
            if (event['type'] == 'announcements') {
              accept(event['data'], current);
            }
          } catch (_) {}
        },
        onError: (_) => disconnected(current),
        onDone: () => disconnected(current),
      );
      heartbeat = Timer.periodic(const Duration(seconds: 35), (_) {
        if (current == generation) {
          try {
            ws.add('ping');
          } catch (_) {
            disconnected(current);
          }
        }
      });
    } catch (_) {
      disconnected(current);
    }
  }

  void disconnected(int current) {
    if (!mounted || !active || current != generation) return;
    setState(() => online = false);
    heartbeat?.cancel();
    if (retry?.isActive != true) {
      // The same HTTP snapshot covers both cards when WebSocket upgrades are blocked.
      unawaited(
        stateOf(context).service
            .request('/announcements')
            .then((data) {
              accept(data, current, live: false);
            })
            .catchError((_) {}),
      );
      retry = Timer(const Duration(seconds: 10), connect);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active) {
      unawaited(connect());
    } else {
      stop();
    }
  }

  @override
  void dispose() {
    active = false;
    stop();
    rotation?.cancel();
    controller.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void details(String title, String content) => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: SelectableText(content, style: const TextStyle(height: 1.8)),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('知道了')),
      ],
    ),
  );

  Widget announcementCard() => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: Theme.of(context).brightness == Brightness.dark
            ? [const Color(0xff3c3456), const Color(0xff53405d)]
            : [const Color(0xffede5ff), const Color(0xffffeaf2)],
      ),
    ),
    padding: const EdgeInsets.all(34),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.campaign_outlined, color: violet),
            const SizedBox(width: 10),
            Text('星屿公告栏', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            Text(
              online ? '实时公告' : '上次公告 · 等待连接',
              style: const TextStyle(fontSize: 11, color: violet),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: notices.isEmpty
              ? const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '暂时没有新公告。\n愿你今天也收获一份好心情。',
                    style: TextStyle(fontSize: 20, height: 1.8),
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final notice in notices)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            text(notice['title']),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            text(notice['content']),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.north_east, size: 18),
                          onTap: () => details(
                            text(notice['title']),
                            text(notice['content']),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    ),
  );

  Widget discoveryCard() => Material(
    child: InkWell(
      onTap: () =>
          details(text(discovery['title']), text(discovery['content'])),
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xffb4a1ed), Color(0xffded0f0), Color(0xffedd9e9)],
          ),
        ),
        child: Stack(
          children: [
            const Positioned.fill(
              child: CustomPaint(painter: UniversePainter()),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 38, vertical: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'YOUR LITTLE UNIVERSE',
                    style: TextStyle(
                      color: Colors.white,
                      letterSpacing: 2,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    text(discovery['title']),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: Text(
                      text(discovery['content']),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '你的每一种喜欢，都值得被收藏  ›',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 268,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification && n.dragDetails != null) {
                touched = DateTime.now();
              }
              return false;
            },
            child: PageView(
              controller: controller,
              onPageChanged: (p) => setState(() => page = p),
              children: [announcementCard(), discoveryCard()],
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 2; i++)
            Tooltip(
              message: i == 0 ? '公告' : '发现',
              child: InkWell(
                onTap: () {
                  touched = DateTime.now();
                  controller.animateToPage(
                    i,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOut,
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == page ? 22 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == page ? violet : violet.withValues(alpha: .2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
        ],
      ),
    ],
  );
}

class UniversePainter extends CustomPainter {
  const UniversePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withValues(alpha: .13);
    canvas.drawCircle(Offset(size.width * .84, size.height * .1), 190, p);
    p
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: .3);
    canvas.drawCircle(Offset(size.width * .85, size.height * .63), 91, p);
    p
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: .65);
    final random = Random(45);
    for (var i = 0; i < 35; i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        random.nextDouble() * 1.8 + .5,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant UniversePainter oldDelegate) => false;
}

class CategoryTabsPage extends StatefulWidget {
  const CategoryTabsPage({super.key});
  @override
  State<CategoryTabsPage> createState() => _CategoryTabsPageState();
}

class _CategoryTabsPageState extends State<CategoryTabsPage> {
  int parent = 0, selected = 0, page = 1;
  bool restored = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!restored) {
      restored = true;
      final saved = object(
        object(
          stateOf(context).local['categoryCursor'],
        )['${stateOf(context).uid}'],
      );
      parent = number(saved['parent']);
      selected = number(saved['selected']);
      page = number(saved['page']);
      if (page < 1) page = 1;
    }
  }

  void remember() {
    final app = stateOf(context),
        all = object(stateOf(context).local['categoryCursor']);
    all['${app.uid}'] = {'parent': parent, 'selected': selected, 'page': page};
    app.local['categoryCursor'] = all;
    unawaited(app.persist());
  }

  @override
  Widget build(BuildContext context) {
    final app = stateOf(context);
    return AsyncPane(
      cacheKey: 'category-tabs',
      load: () async {
        final result = await app.get('category/list', {
          'all': 1,
          'type': 'post',
        });
        app.categories = rows(result['data']);
        return result;
      },
      builder: (r, reload) {
        final roots = rows(r['data']);
        if (roots.isEmpty) return const Blank('分类暂不可用', '请联网后重新打开分类');
        final root = roots.firstWhere(
              (c) => number(c['id']) == parent,
              orElse: () => roots.first,
            ),
            rootId = number(root['id']);
        final subs = rows(root['children']),
            active =
                selected == rootId ||
                    rows(root['children'])
                        .any((n) => number(n['id']) == selected)
                ? selected
                : rootId;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
              child: Row(
                children: [
                  const Icon(Icons.interests_rounded, color: violet),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '兴趣频道',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '排版设置',
                    onPressed: () => openRoute(
                      context,
                      const DeskRoute('appearance', '阅读与外观'),
                    ),
                    icon: const Icon(Icons.dashboard_customize_outlined),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        for (final node in roots)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(text(node['name'])),
                              selected: number(node['id']) == rootId,
                              onSelected: (_) => setState(() {
                                parent = number(node['id']);
                                selected = 0;
                                page = 1;
                                remember();
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (subs.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          for (final node in [
                            {'id': rootId, 'name': '全部'},
                            ...subs,
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(text(node['name'])),
                                selected: number(node['id']) == active,
                                onSelected: (_) => setState(() {
                                  selected = number(node['id']);
                                  page = 1;
                                  remember();
                                }),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: DeskScope(
                app: app,
                open: (next) {
                  if (next.kind == 'posts' && next.id == active) {
                    setState(() {
                      page = next.page;
                      remember();
                    });
                  } else {
                    openRoute(context, next);
                  }
                },
                child: PostListPage(
                  DeskRoute(
                    'posts',
                    text(
                      (subs.firstWhere(
                        (n) => number(n['id']) == active,
                        orElse: () => root,
                      ))['name'],
                    ),
                    id: active,
                    page: page,
                  ),
                  key: ValueKey('category:$active:$page'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
