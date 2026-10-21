import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/reader.dart';
import '../ui/shared.dart';

class ArticlePage extends StatelessWidget {
  final int id;
  const ArticlePage(this.id, {super.key});
  @override
  Widget build(BuildContext context) {
    final app = stateOf(context);
    return AsyncPane(
      load: () => app.get('post/info', {
        'id': id,
        'include': 'user,tags,categories,favorited,upvoted',
      }),
      builder: (result, reload) {
        final post = object(result['data']),
            author = object(post['user']),
            document = ReaderDocument.parse(text(post['content']));
        return PageBody(
          width: 1140,
          child: SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in rows(post['categories']))
                      ActionChip(
                        label: Text(text(c['name'])),
                        onPressed: () => openRoute(
                          context,
                          DeskRoute(
                            'posts',
                            text(c['name']),
                            id: number(c['id']),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  text(post['title']),
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Avatar(
                      author,
                      radius: 23,
                      onTap: () => openRoute(
                        context,
                        DeskRoute('author', '作者主页', id: number(author['id'])),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextButton(
                            onPressed: () => openRoute(
                              context,
                              DeskRoute(
                                'author',
                                '作者主页',
                                id: number(author['id']),
                              ),
                            ),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 25),
                              alignment: Alignment.centerLeft,
                            ),
                            child: Text(text(author['nickname'], '仓库作者')),
                          ),
                          Text(
                            '${dateText(post['created_at'])}  ·  ${number(post['view_count'])} 次阅读',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    FavoriteButton(post),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '复制作品链接',
                      onPressed: () =>
                          copy(context, '$siteOrigin/archives/$id'),
                      icon: const Icon(Icons.ios_share_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                Surface(
                  padding: const EdgeInsets.all(36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RichContent(document.content),
                      for (final resource in document.resources)
                        Padding(
                          padding: const EdgeInsets.only(top: 22),
                          child: Surface(
                            color: violet.withValues(alpha: .07),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  resource.title,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                if (resource.info.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  SelectableText(resource.info),
                                ],
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    for (final link in resource.links.entries)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          FilledButton.tonalIcon(
                                            onPressed: () =>
                                                openLink(context, link.value),
                                            icon: const Icon(
                                              Icons.cloud_download_outlined,
                                              size: 17,
                                            ),
                                            label: Text(link.key),
                                          ),
                                          IconButton(
                                            onPressed: () =>
                                                copy(context, link.value),
                                            tooltip: '复制资源链接',
                                            icon: const Icon(
                                              Icons.copy,
                                              size: 17,
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 28),
                      const Divider(),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () =>
                                openLink(context, '$siteOrigin/archives/$id'),
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('在官网查看原文'),
                          ),
                          const Spacer(),
                          const Icon(Icons.format_size, size: 18),
                          SizedBox(
                            width: 130,
                            child: Slider(
                              min: 13,
                              max: 26,
                              value: app.fontSize,
                              onChanged: (v) => app.setFont(v),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                CommentsPane(id, locked: post['is_locked'] == true),
                const SizedBox(height: 35),
                _HistoryMarker(post),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HistoryMarker extends StatefulWidget {
  final Json post;
  const _HistoryMarker(this.post);
  @override
  State<_HistoryMarker> createState() => _HistoryMarkerState();
}

class _HistoryMarkerState extends State<_HistoryMarker> {
  bool saved = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!saved) {
      saved = true;
      stateOf(context).addHistory(widget.post).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class FavoriteButton extends StatefulWidget {
  final Json post;
  const FavoriteButton(this.post, {super.key});
  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final favored = widget.post['favorited'] == true;
    return FilledButton.tonalIcon(
      onPressed: busy
          ? null
          : () async {
              setState(() => busy = true);
              await action(context, () async {
                await stateOf(context).post(
                  favored ? 'post/unfavorite' : 'post/favorite',
                  {'id': widget.post['id']},
                );
                if (mounted) {
                  setState(() => widget.post['favorited'] = !favored);
                }
              });
              if (mounted) setState(() => busy = false);
            },
      icon: Icon(
        favored ? Icons.star_rounded : Icons.star_border_rounded,
        size: 18,
      ),
      label: Text(favored ? '已收藏' : '收藏作品'),
    );
  }
}

Future<String?> composeText(
  BuildContext context,
  String title, {
  String hint = '写下想说的话…',
  String initial = '',
  String submit = '发布',
  int max = 5000,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 560,
        child: TextField(
          controller: controller,
          autofocus: true,
          minLines: 5,
          maxLines: 12,
          maxLength: max,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(c, controller.text.trim());
            }
          },
          child: Text(submit),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

class CommentsPane extends StatefulWidget {
  final int post, root;
  final bool locked;
  const CommentsPane(
    this.post, {
    super.key,
    this.root = 0,
    this.locked = false,
  });
  @override
  State<CommentsPane> createState() => _CommentsPaneState();
}

class _CommentsPaneState extends State<CommentsPane> {
  int page = 1, reload = 0;
  Future<Json> load() async {
    final app = stateOf(context), p = widget.post;
    final response = await app.get('comment/list', {
      'post_id': p,
      'parent_id': widget.root,
      'page': page,
      'per_page': 8,
      'order_by': 'created_at',
      'order': widget.root == 0 ? 'desc' : 'asc',
      'include': 'user,children.user,replyToUser',
      'with[0]': 'user',
      'with[1]': 'children',
    });
    final comments = rows(response['data']),
        ids = [
          ...comments,
          for (final c in comments) ...rows(object(c['children'])['data']),
        ].map((c) => c['id']).toList();
    if (ids.isNotEmpty) {
      try {
        final likes = await app.get('user/followableIdList', {
          'relation': 'upvote',
          'type': 'comment',
          for (var i = 0; i < ids.length; i++) 'ids[$i]': ids[i],
        });
        response['_likes'] = likes['data'];
      } catch (_) {}
    }
    return response;
  }

  void refresh() {
    if (mounted) setState(() => reload++);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Heading(
        widget.root == 0 ? '作品评论' : '讨论回复',
        widget.locked ? '作者已关闭评论' : '每一份交流，都让热爱更近一点。',
        trailing: widget.root == 0 && !widget.locked
            ? FilledButton.tonalIcon(
                onPressed: () async {
                  final value = await composeText(context, '发表评论');
                  if (value != null && context.mounted) {
                    await action(context, () async {
                      await stateOf(context).post('comment/create', {
                        'post_id': widget.post,
                        'content': value,
                        'include': 'user',
                      });
                      refresh();
                    }, success: '评论已发布');
                  }
                },
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('写评论'),
              )
            : null,
      ),
      SizedBox(
        height: widget.root == 0 ? null : 590,
        child: AsyncPane(
          key: ValueKey('$page:$reload'),
          load: load,
          builder: (result, _) {
            final likes = (result['_likes'] as List? ?? []).map(number).toSet(),
                comments = rows(result['data']);
            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (comments.isEmpty) const Blank('还没有评论', '第一条留言，也许就从你开始。'),
                for (final c in comments)
                  CommentTile(
                    c,
                    widget.post,
                    locked: widget.locked,
                    liked: likes,
                    onChange: refresh,
                  ),
                Pagination(result, page, (p) => setState(() => page = p)),
              ],
            );
            return widget.root == 0
                ? content
                : SingleChildScrollView(child: content);
          },
        ),
      ),
    ],
  );
}

class CommentTile extends StatelessWidget {
  final Json comment;
  final int post;
  final Set<int> liked;
  final bool locked, child;
  final VoidCallback onChange;
  const CommentTile(
    this.comment,
    this.post, {
    super.key,
    required this.liked,
    required this.onChange,
    this.locked = false,
    this.child = false,
  });
  @override
  Widget build(BuildContext context) {
    final user = object(comment['user']),
        app = stateOf(context),
        root = number(comment['parent_id']) > 0
            ? number(comment['parent_id'])
            : number(comment['id']);
    return Padding(
      padding: EdgeInsets.only(bottom: 16, left: child ? 24 : 0),
      child: Surface(
        padding: const EdgeInsets.all(20),
        color: child ? violet.withValues(alpha: .04) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Avatar(
                  user,
                  radius: 17,
                  onTap: () => openRoute(
                    context,
                    DeskRoute('author', '作者主页', id: number(user['id'])),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text(user['nickname'], '已注销用户'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  dateText(comment['created_at']),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            RichContent(text(comment['content']), fontSize: 15),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                TextButton.icon(
                  onPressed: () => action(context, () async {
                    await app.post(
                      liked.contains(number(comment['id']))
                          ? 'comment/unvote'
                          : 'comment/vote',
                      {'id': comment['id']},
                    );
                    onChange();
                  }),
                  icon: Icon(
                    liked.contains(number(comment['id']))
                        ? Icons.favorite
                        : Icons.favorite_border,
                    size: 15,
                  ),
                  label: Text('${number(comment['vote_count'])}'),
                ),
                if (!locked)
                  TextButton(
                    onPressed: () async {
                      final reply = await composeText(
                        context,
                        '回复 ${text(user['nickname'])}',
                      );
                      if (reply != null && context.mounted) {
                        await action(context, () async {
                          await app.post('comment/create', {
                            'post_id': post,
                            'parent_id': root,
                            'reply_to_id': comment['id'],
                            'content': reply,
                            'include': 'user',
                          });
                          onChange();
                        }, success: '回复已发布');
                      }
                    },
                    child: const Text('回复'),
                  ),
                if (number(comment['user_id']) == app.uid)
                  TextButton(
                    onPressed: () async {
                      if (await confirm(
                            context,
                            '删除这条评论？',
                            '删除后无法恢复。',
                            action: '删除',
                          ) &&
                          context.mounted) {
                        await action(context, () async {
                          await app.post('comment/delete', {
                            'id': comment['id'],
                          });
                          onChange();
                        });
                      }
                    },
                    child: const Text('删除'),
                  ),
              ],
            ),
            if (!child) ...[
              for (final reply in rows(object(comment['children'])['data']))
                CommentTile(
                  reply,
                  post,
                  liked: liked,
                  onChange: onChange,
                  locked: locked,
                  child: true,
                ),
              if (number(comment['comment_count']) > 0 ||
                  number(object(object(comment['children'])['meta'])['total']) >
                      0 ||
                  rows(object(comment['children'])['data']).isNotEmpty)
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (c) => Dialog(
                      child: SizedBox(
                        width: 760,
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: CommentsPane(post, root: root, locked: locked),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('查看讨论的全部回复  →'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class AuthorPage extends StatelessWidget {
  final int id;
  const AuthorPage(this.id, {super.key});
  @override
  Widget build(BuildContext context) => AsyncPane(
    load: () => stateOf(context).get('user/info', {'id': id}),
    builder: (result, reload) {
      final user = object(result['data']);
      return PageBody(
        width: 1000,
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Cover(text(user['banner']), height: 200),
            ),
            Transform.translate(
              offset: const Offset(0, -40),
              child: Avatar(user, radius: 48),
            ),
            Text(
              text(user['nickname']),
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => copy(context, '$id', '已复制UID'),
              icon: const Icon(Icons.copy, size: 14),
              label: Text('UID  $id'),
            ),
            const SizedBox(height: 10),
            SelectableText(
              text(user['description'], '这个人很神秘，暂时没有留下简介。'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 26),
            Wrap(
              spacing: 16,
              runSpacing: 14,
              children: [
                Chip(label: Text('Lv.${number(user['level'])}')),
                Chip(label: Text('${number(user['post_count'])} 篇投稿')),
                Chip(label: Text('${number(user['follower_count'])} 位关注者')),
              ],
            ),
            const SizedBox(height: 30),
            Wrap(
              spacing: 16,
              runSpacing: 14,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => openRoute(
                    context,
                    DeskRoute(
                      'authorPosts',
                      '${text(user['nickname'])}的投稿',
                      id: id,
                    ),
                  ),
                  icon: const Icon(Icons.grid_view),
                  label: const Text('浏览作者作品'),
                ),
                if (id != stateOf(context).uid)
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        openRoute(context, DeskRoute('dm', '私信', id: id)),
                    icon: const Icon(Icons.mail_outline),
                    label: const Text('给作者发私信'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => openLink(context, '$siteOrigin/user/$id'),
                  icon: const Icon(Icons.open_in_new, size: 17),
                  label: const Text('官网主页'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
