import 'following.dart';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/reader.dart';
import '../core/comment_content.dart';
import '../ui/comment_composer.dart';
import '../ui/shared.dart';

class ArticlePage extends StatelessWidget {
  final int id;
  final bool ownerOnly;
  const ArticlePage(this.id, {super.key, this.ownerOnly = false});
  @override
  Widget build(BuildContext context) {
    final app = stateOf(context), owner = app.uid, generation = app.generation;
    return AsyncPane(
      cacheKey: ownerOnly ? null : 'article:$id',
      articlePlaceholder: true,
      load: () async {
        if (ownerOnly && owner <= 0) throw ApiFailure(401, '请先登录草稿所属账号');
        final result = await app.get('post/info', {
          'id': id,
          'include': ownerOnly
              ? 'user,tags,categories'
              : 'user,tags,categories,favorited,upvoted',
          if (ownerOnly) 'exclude_view': 1,
        });
        final post = object(result['data']);
        if (ownerOnly &&
            (app.uid != owner ||
                app.generation != generation ||
                number(post['user_id']) != owner)) {
          throw ApiFailure(403, '仅作者本人可以查看这篇草稿');
        }
        return result;
      },
      builder: (result, reload) {
        if (ownerOnly && (app.uid != owner || app.generation != generation)) {
          return const Center(child: Text('账号已切换，请重新打开草稿'));
        }
        final post = object(result['data']),
            author = object(post['user']),
            document = ReaderDocument.parse(text(post['content']));
        return PageBody(
          width: 1140,
          child: SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ownerOnly)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Surface(
                      color: violet.withValues(alpha: .07),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline_rounded, color: violet),
                          const SizedBox(width: 10),
                          const Expanded(child: Text('作者专属预览 · 未公开内容仅本人可见')),
                          TextButton.icon(
                            onPressed: () => openRoute(
                              context,
                              DeskRoute('editor', '编辑投稿', id: id),
                            ),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('继续编辑'),
                          ),
                        ],
                      ),
                    ),
                  ),
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
                  style: Theme.of(context).textTheme.headlineLarge
                      ?.copyWith(fontWeight: FontWeight.w800, height: 1.45),
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
                    if (!ownerOnly) FavoriteButton(post),
                    if (!ownerOnly) const SizedBox(width: 8),
                    if (!ownerOnly)
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
                  padding: EdgeInsets.all(
                    MediaQuery.sizeOf(context).width < 700 ? 16 : 36,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RichContent(
                        document.content,
                        maxImageHeight: 520,
                        maxImageWidth: 760,
                      ),
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
                                if (resource.details.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  SelectableText(resource.details),
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
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: () => openLink(
                              context,
                              '$siteOrigin/archives/$id${ownerOnly ? '/preview' : ''}',
                            ),
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: Text(ownerOnly ? '在官网查看草稿' : '在官网查看原文'),
                          ),
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
                if (!ownerOnly)
                  CommentsPane(id, locked: post['is_locked'] == true),
                const SizedBox(height: 35),
                if (!ownerOnly) _HistoryMarker(post),
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

int commentReplyCount(Json comment) {
  final children = object(comment['children']), meta = object(children['meta']);
  return [
    number(comment['comment_count']),
    number(meta['total']),
    number(object(meta['pagination'])['total']),
    rows(children['data']).length,
  ].fold(0, (a, b) => a > b ? a : b);
}

Future<void> showDiscussionReplies(
  BuildContext context, {
  required int post,
  required int root,
  required bool locked,
  required VoidCallback onChanged,
}) async {
  final scope = DeskScope.of(context),
      owner = stateOf(context).uid,
      generation = stateOf(context).generation;
  bool changed = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AnimatedBuilder(
      animation: scope.app,
      builder: (_, _) => DeskScope(
        app: scope.app,
        open: (route) {
          Navigator.of(dialogContext).pop();
          if (context.mounted) scope.open(route);
        },
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 22,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: SizedBox(
              width: 820,
              height: MediaQuery.sizeOf(dialogContext).height * .86,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Heading(
                      '讨论回复',
                      '按时间顺序查看这条讨论，支持回复与点赞。',
                      trailing: IconButton(
                        tooltip: '关闭讨论',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                    Expanded(
                      child:
                          scope.app.uid != owner ||
                              scope.app.generation != generation
                          ? const Blank(
                              '账号状态已变化',
                              '请关闭讨论，再重新打开。',
                              icon: Icons.person_outline_rounded,
                            )
                          : CommentsPane(
                              post,
                              root: root,
                              locked: locked,
                              showHeading: false,
                              onChanged: () => changed = true,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (changed && context.mounted) onChanged();
}

class CommentsPane extends StatefulWidget {
  final int post, root;
  final bool locked, showHeading;
  final VoidCallback? onChanged;
  const CommentsPane(
    this.post, {
    super.key,
    this.root = 0,
    this.locked = false,
    this.showHeading = true,
    this.onChanged,
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
      'include': widget.root == 0
          ? 'user,children.user,replyToUser'
          : 'user,replyToUser',
      'with[0]': 'user',
      if (widget.root == 0) 'with[1]': 'children',
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
    if (mounted) {
      setState(() => reload++);
      widget.onChanged?.call();
    }
  }

  Widget results() => AsyncPane(
    key: ValueKey('$page:$reload'),
    load: load,
    builder: (result, _) {
      final likes = (result['_likes'] as List? ?? []).map(number).toSet(),
          comments = rows(result['data']);
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (comments.isEmpty)
            Blank(
              widget.root == 0 ? '还没有评论' : '这条讨论暂无回复',
              widget.root == 0 ? '写下第一条评论，和大家聊聊这部作品。' : '回复可能已删除，或还没有人加入讨论。',
              icon: Icons.chat_bubble_outline_rounded,
            ),
          for (final c in comments)
            CommentTile(
              c,
              widget.post,
              locked: widget.locked,
              child: widget.root != 0,
              liked: likes,
              onChange: refresh,
            ),
          Pagination(result, page, (p) => setState(() => page = p)),
        ],
      );
      return widget.root == 0
          ? content
          : Scrollbar(child: SingleChildScrollView(child: content));
    },
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (widget.showHeading)
        Heading(
          widget.root == 0 ? '作品评论' : '讨论回复',
          widget.locked ? '作者已关闭评论' : '交流感受，也欢迎补充作品信息。',
          trailing: widget.root == 0 && !widget.locked
              ? FilledButton.tonalIcon(
                  onPressed: () async {
                    final value = await composeComment(context, '发表评论');
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
      if (widget.root == 0) results() else Expanded(child: results()),
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
            RichContent(
              renderCommentContent(text(comment['content'])),
              fontSize: 15,
              maxImageHeight: 300,
              maxImageWidth: 480,
            ),
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
                  TextButton.icon(
                    onPressed: () async {
                      final reply = await composeComment(
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
                    icon: const Icon(Icons.reply_rounded, size: 17),
                    label: const Text('回复'),
                  ),
                if (number(comment['user_id']) == app.uid)
                  TextButton.icon(
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
                    icon: const Icon(Icons.delete_outline_rounded, size: 17),
                    label: const Text('删除'),
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
              if (commentReplyCount(comment) > 0)
                TextButton.icon(
                  onPressed: () => showDiscussionReplies(
                    context,
                    post: post,
                    root: root,
                    locked: locked,
                    onChanged: onChange,
                  ),
                  icon: const Icon(Icons.forum_outlined, size: 17),
                  label: Text('查看全部回复 · ${commentReplyCount(comment)}'),
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
    cacheKey: 'author:$id',
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
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
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
                Chip(label: Text('${number(user['follower_count'])} 位官网关注者')),
              ],
            ),
            AuthorFollowInfo(id),
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
                if (id != stateOf(context).uid) FollowButton(id, author: user),
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
