import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/quick_feed.dart';
import '../ui/shared.dart';
import 'discovery.dart';

class QuickFeedPage extends StatefulWidget {
  final QuickFeedStore store;
  const QuickFeedPage(this.store, {super.key});
  @override
  State<QuickFeedPage> createState() => _QuickFeedPageState();
}

class _QuickFeedPageState extends State<QuickFeedPage> {
  final scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    scroll.addListener(more);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.store.posts.isEmpty) unawaited(widget.store.load());
    });
  }

  void more() {
    if (scroll.hasClients && scroll.position.extentAfter < 650) {
      unawaited(widget.store.load());
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final feed = widget.store, scheme = Theme.of(context).colorScheme;
      return LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 650;
          final columns = compact
              ? (constraints.maxWidth < 330 ? 1 : 2)
              : (constraints.maxWidth / 260).floor().clamp(2, 5);
          return RefreshIndicator(
            onRefresh: () => feed.load(refresh: true),
            child: CustomScrollView(
              key: const PageStorageKey('quick-feed-scroll'),
              controller: scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 28,
                    16,
                    compact ? 16 : 28,
                    14,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: violet.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: const Icon(
                                Icons.bolt_rounded,
                                color: violet,
                                size: 25,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '快撸',
                                    style: TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    '下拉换一批 · 继续滑动发现更多',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              key: const Key('quick-feed.refresh'),
                              tooltip: '换一批推荐',
                              onPressed: feed.loading
                                  ? null
                                  : () async {
                                      await feed.load(refresh: true);
                                      if (mounted &&
                                          scroll.hasClients &&
                                          feed.error.isEmpty) {
                                        scroll.jumpTo(0);
                                      }
                                    },
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final category in feed.preferredCategories)
                              Chip(
                                avatar: const Icon(
                                  Icons.favorite_border_rounded,
                                  size: 14,
                                  color: violet,
                                ),
                                label: Text(
                                  text(category['name']),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            Text(
                              feed.preferredCategories.isEmpty
                                  ? '先随便看看，阅读后推荐会更懂你'
                                  : '根据本机阅读足迹推荐，也为你留一点新发现',
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        if (feed.refreshing)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                      ],
                    ),
                  ),
                ),
                if (feed.posts.isNotEmpty)
                  SliverPadding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 16 : 28,
                    ),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => PostCard(
                          feed.posts[index],
                          key: ValueKey('quick.${feed.posts[index]['id']}'),
                        ),
                        childCount: feed.posts.length,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisExtent: compact ? 292 : 306,
                        crossAxisSpacing: compact ? 12 : 18,
                        mainAxisSpacing: compact ? 14 : 20,
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: feed.loading && feed.posts.isEmpty
                        ? Column(
                            children: [
                              const SizedBox(height: 60),
                              const CircularProgressIndicator(strokeWidth: 2),
                              const SizedBox(height: 14),
                              Text(
                                '正在为你挑选作品',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              if (feed.error.isNotEmpty)
                                Text(feed.error, textAlign: TextAlign.center),
                              if (feed.loading)
                                const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else if (feed.exhausted ||
                                  feed.posts.isEmpty ||
                                  feed.error.isNotEmpty)
                                TextButton.icon(
                                  onPressed: () =>
                                      feed.load(refresh: feed.exhausted),
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    feed.exhausted ? '换一批继续发现' : '重新加载',
                                  ),
                                )
                              else
                                TextButton.icon(
                                  onPressed: feed.load,
                                  icon: const Icon(Icons.expand_more_rounded),
                                  label: const Text('继续看更多'),
                                ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
