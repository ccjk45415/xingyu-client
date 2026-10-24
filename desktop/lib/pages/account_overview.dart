import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/media.dart';
import '../ui/shared.dart';
import 'diagnostics.dart';
import 'checkin.dart';

const _rose = Color(0xffec7198);

/// A compact personal center: profile, three stats, shortcuts and creation.
class AccountOverview extends StatelessWidget {
  const AccountOverview({super.key});

  Widget profile(BuildContext context) {
    final app = stateOf(context), user = app.user ?? {};
    return Surface(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Avatar(
                user,
                radius: 29,
                onTap: () => openRoute(
                  context,
                  DeskRoute('author', '我的主页', id: app.uid),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text(user['nickname'], '仓库用户'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        InkWell(
                          onTap: () => copy(context, '${app.uid}', '已复制UID'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Text(
                              'UID ${app.uid}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _rose.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            'LV${number(user['level'])}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _rose,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '编辑资料',
                onPressed: () =>
                    openRoute(context, const DeskRoute('profile', '编辑个人资料')),
                icon: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          if (text(user['description']).trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                text(user['description']),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          const SizedBox(height: 6),
          const _AccountMetrics(),
        ],
      ),
    );
  }

  Widget shortcuts(BuildContext context) => Surface(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    child: _ShortcutGrid(
      items: const [
        ('我的收藏', Icons.bookmark_border_rounded, 'favorites'),
        ('阅读足迹', Icons.history_rounded, 'history'),
        ('我的评论', Icons.chat_bubble_outline_rounded, 'myComments'),
        ('独立私信', Icons.mail_outline_rounded, 'inbox'),
      ],
    ),
  );

  Widget creator(BuildContext context) => Surface(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '创作中心',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            FilledButton.icon(
              key: const Key('account.new-post'),
              style: FilledButton.styleFrom(
                backgroundColor: _rose,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                minimumSize: const Size(0, 36),
              ),
              onPressed: () =>
                  openRoute(context, const DeskRoute('editor', '新建投稿')),
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('新建投稿', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 5, bottom: 8),
          child: Text(
            'AI 投稿助手，让灵感更快变成作品',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        const _ShortcutGrid(
          items: [
            ('我的投稿', Icons.edit_note_rounded, 'manage'),
            ('本机草稿', Icons.drafts_outlined, 'drafts'),
            ('等级与积分', Icons.military_tech_outlined, 'logs'),
          ],
          columns: 3,
          color: _rose,
        ),
      ],
    ),
  );

  Widget services(BuildContext context) => Surface(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    child: Column(
      children: [
        for (final item in [
          ('通知', Icons.notifications_none_rounded, 'noticeCenter'),
          ('关注动态', Icons.rss_feed_rounded, 'followingFeed'),
          ('设置', Icons.settings_outlined, 'settings'),
        ])
          ListTile(
            visualDensity: VisualDensity.compact,
            minTileHeight: 48,
            leading: Icon(item.$2, size: 22, color: violet),
            title: Text(item.$1, style: const TextStyle(fontSize: 14)),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Colors.grey,
            ),
            onTap: () => openRoute(
              context,
              DeskRoute(
                item.$3,
                item.$1,
                filter: item.$3 == 'notifications' ? 'reply' : '',
              ),
            ),
          ),
        ListTile(
          visualDensity: VisualDensity.compact,
          minTileHeight: 48,
          leading: const Icon(
            Icons.bug_report_outlined,
            size: 22,
            color: violet,
          ),
          title: const Text('诊断信息', style: TextStyle(fontSize: 14)),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: Colors.grey,
          ),
          onTap: () => showDiagnostics(context),
        ),
      ],
    ),
  );

  Future<void> logout(BuildContext context) async {
    final app = stateOf(context);
    if (await confirm(context, '退出当前账号？', '会清除本机登录和聊天认证，保留本机阅读足迹与草稿。') &&
        context.mounted) {
      MediaCache.clear();
      await app.logout();
    }
  }

  @override
  Widget build(BuildContext context) => PageBody(
    key: const Key('account.overview'),
    width: 1120,
    child: LayoutBuilder(
      builder: (context, size) {
        final wide = size.maxWidth >= 820;
        final left = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            profile(context),
            const SizedBox(height: 12),
            const CheckinCard(),
            const SizedBox(height: 12),
            shortcuts(context),
          ],
        );
        final right = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            creator(context),
            const SizedBox(height: 12),
            services(context),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '个人中心',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新资料',
                      onPressed: () =>
                          action(context, stateOf(context).refreshUser),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 340, child: left),
                  const SizedBox(width: 20),
                  Expanded(child: right),
                ],
              )
            else ...[
              left,
              const SizedBox(height: 12),
              right,
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: () => logout(context),
                child: const Text(
                  '退出登录',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _ShortcutGrid extends StatelessWidget {
  final List<(String, IconData, String)> items;
  final int columns;
  final Color color;
  const _ShortcutGrid({
    required this.items,
    this.columns = 4,
    this.color = violet,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) => Wrap(
      children: [
        for (final item in items)
          SizedBox(
            width: size.maxWidth / columns,
            child: InkWell(
              key: ValueKey('account.shortcut.${item.$3}'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => openRoute(context, DeskRoute(item.$3, item.$1)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 2,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(item.$2, color: color, size: 25),
                    const SizedBox(height: 7),
                    Text(
                      item.$1,
                      maxLines: 1,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _AccountMetrics extends StatefulWidget {
  const _AccountMetrics();
  @override
  State<_AccountMetrics> createState() => _AccountMetricsState();
}

class _AccountMetricsState extends State<_AccountMetrics> {
  String scope = '';
  Json data = {};
  int job = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = stateOf(context),
        key =
            '${stateOf(context).uid}:${stateOf(context).generation}:${stateOf(context).socialRevision}:${stateOf(context).verified}';
    if (scope == key) return;
    scope = key;
    data = {};
    final request = ++job;
    if (app.verified) {
      unawaited(() async {
        try {
          final value = await app.social('/dm/v1/follows/status');
          if (mounted && request == job) setState(() => data = value);
        } catch (_) {
          /* Keep the compact placeholder; the follow list can retry. */
        }
      }());
    }
  }

  @override
  void dispose() {
    job++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = stateOf(context);
    return Row(
      children: [
        for (final item in [
          ('投稿', '${number(app.user?['post_count'])}', 'manage', ''),
          (
            '关注',
            data['following_count'] == null
                ? '—'
                : '${number(data['following_count'])}',
            'followPeople',
            'following',
          ),
          (
            '粉丝',
            data['follower_count'] == null
                ? '—'
                : '${number(data['follower_count'])}',
            'followPeople',
            'followers',
          ),
        ])
          Expanded(
            child: InkWell(
              onTap: () => openRoute(
                context,
                DeskRoute(item.$3, item.$1, filter: item.$4),
              ),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Column(
                  children: [
                    Text(
                      item.$2,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.$1,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
