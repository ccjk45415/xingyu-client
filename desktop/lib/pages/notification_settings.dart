import 'dart:async';

import 'package:flutter/material.dart';

import '../core/in_app_notices.dart';
import '../ui/shared.dart';

IconData noticeIcon(String kind) => switch (kind) {
  'dm' => Icons.mail_outline_rounded,
  'chatMention' => Icons.alternate_email_rounded,
  'postReply' => Icons.forum_outlined,
  'commentReply' => Icons.reply_rounded,
  'like' => Icons.favorite_border,
  _ => Icons.notifications_none_rounded,
};

String noticeKind(String kind) => switch (kind) {
  'dm' => '私信',
  'chatMention' => '聊天室艾特',
  'postReply' => '帖子回复',
  'commentReply' => '评论回复',
  'like' => '点赞',
  _ => '新消息',
};

DeskRoute noticeRoute(AppNotice notice) => switch (notice.kind) {
  'dm' => DeskRoute('dm', '私信', id: notice.target),
  'chatMention' => DeskRoute('chat', '聊天室', filter: notice.channel),
  _ when notice.target > 0 => DeskRoute('article', '作品详情', id: notice.target),
  _ => const DeskRoute('notifications', '回复与点赞', filter: 'reply'),
};

void openNotice(BuildContext context, AppNotice notice) {
  stateOf(context).notices.read(notice);
  openRoute(context, noticeRoute(notice));
}

class NotificationSettingsPage extends StatelessWidget {
  const NotificationSettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = stateOf(context), notices = app.notices;
    return AnimatedBuilder(
      animation: notices,
      builder: (context, _) => PageBody(
        width: 820,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Heading('通知设置', '与你有关的消息，按你的习惯提醒。'),
            Surface(
              color: violet.withValues(alpha: .06),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const IconBadge(Icons.notifications_none_rounded),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '消息不漏看，提醒由你决定',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          notices.system.explanation,
                          style: const TextStyle(fontSize: 12, height: 1.7),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Surface(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const IconBadge(Icons.notifications_none_rounded),
                title: const Text('开启应用内提醒'),
                subtitle: const Text('显示新消息横幅和未读标记'),
                value: notices.enabledAll,
                onChanged: (value) => action(
                  context,
                  () => notices.setPreference('enabled', value),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Surface(
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const IconBadge(
                      Icons.notifications_active_outlined,
                    ),
                    title: const Text('应用外通知'),
                    subtitle: Text(
                      notices.systemStatus['granted'] == true
                          ? '系统通知已允许 · 后台提醒新消息'
                          : '首次开启时申请系统通知权限',
                    ),
                    value: notices.systemEnabled,
                    onChanged: notices.enabledAll
                        ? (value) => action(
                            context,
                            () => notices.setPreference('system', value),
                          )
                        : null,
                  ),
                  const Divider(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notices.systemStatus['channelBlocked'] == true
                              ? '消息通知渠道已关闭，请在系统设置中开启'
                              : '通知权限、声音和锁屏显示可在系统中调整',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            action(context, notices.system.settings),
                        icon: const Icon(Icons.settings_outlined, size: 16),
                        label: const Text('系统设置'),
                      ),
                    ],
                  ),
                  if (notices.systemEnabled)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        notices.systemStatus['scheduled'] == true
                            ? '后台检查已安排 · 受系统省电调度限制'
                            : notices.systemStatus['supported'] == false
                            ? '当前安装包需要更新，才能使用系统通知'
                            : '电脑端需保持程序运行',
                        style: const TextStyle(fontSize: 12, color: violet),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text('想接收哪些消息', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Surface(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  for (final (key, title, detail) in [
                    ('dm', '私信', '有人通过星屿给你发送私信'),
                    ('chatMention', '聊天室艾特与回复', '频道一或频道二中有人艾特或回复了你'),
                    ('postReply', '帖子回复', '有人回复了你的作品或帖子'),
                    ('commentReply', '评论回复', '有人回复了你的评论'),
                    ('like', '点赞', '有人赞了你的作品或评论'),
                  ])
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      secondary: IconBadge(noticeIcon(key), size: 38),
                      title: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        detail,
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: notices.enabled(key),
                      onChanged: notices.enabledAll
                          ? (value) => action(
                              context,
                              () => notices.setPreference(key, value),
                            )
                          : null,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Surface(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const IconBadge(Icons.shield_outlined),
                title: const Text('在提醒中显示内容预览'),
                subtitle: const Text('默认只显示消息类型与发送者，保护阅读隐私'),
                value: notices.showPreview,
                onChanged: notices.enabledAll
                    ? (value) => action(
                        context,
                        () => notices.setPreference('preview', value),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '${notices.status}。首次启用不会补弹历史消息；聊天室和私信需要先认证仓库账号。设置按当前账号保存在本机。',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
                height: 1.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NoticeCenterPage extends StatelessWidget {
  const NoticeCenterPage({super.key});
  @override
  Widget build(BuildContext context) {
    final notices = stateOf(context).notices;
    return AnimatedBuilder(
      animation: notices,
      builder: (context, _) => PageBody(
        width: 900,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Heading(
              '消息提醒',
              '让每一份回应，都能被看见。',
              trailing: IconButton(
                tooltip: '通知设置',
                icon: const Icon(Icons.tune_rounded),
                onPressed: () => openRoute(
                  context,
                  const DeskRoute('noticeSettings', '通知设置'),
                ),
              ),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => openRoute(
                    context,
                    const DeskRoute('notifications', '回复与点赞', filter: 'reply'),
                  ),
                  icon: const Icon(Icons.reply_rounded, size: 18),
                  label: const Text('回复与点赞'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      openRoute(context, const DeskRoute('inbox', '私信')),
                  icon: const Icon(Icons.mail_outline_rounded, size: 18),
                  label: const Text('私信列表'),
                ),
                TextButton.icon(
                  onPressed: notices.unread == 0 ? null : notices.readAll,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('本机全部已读'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              notices.status,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 20),
            if (notices.entries.isEmpty)
              const Blank(
                '暂时没有新的提醒',
                '首次启用不会补弹历史消息。可以从上方查看原有回复与私信；使用应用时，新的回应会出现在这里。',
                icon: Icons.notifications_none_rounded,
              ),
            for (final notice in notices.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Surface(
                  padding: EdgeInsets.zero,
                  color: notice.read ? null : violet.withValues(alpha: .055),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    leading: IconBadge(noticeIcon(notice.kind)),
                    title: Text(
                      notice.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: notice.read
                            ? FontWeight.w500
                            : FontWeight.w700,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        '${noticeKind(notice.kind)} · ${dateText(notice.time.toIso8601String())}${notices.showPreview && notice.preview.isNotEmpty ? '\n${notice.preview}' : ''}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    trailing: notice.read
                        ? const Icon(Icons.chevron_right_rounded, size: 20)
                        : const Icon(Icons.circle, size: 8, color: violet),
                    onTap: () => openNotice(context, notice),
                  ),
                ),
              ),
            if (notices.entries.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  '保留本次使用中最近 60 条提醒。这里只更改本机提醒状态，不会把官网回复或私信自动标为已读。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    height: 1.8,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class NoticeBell extends StatelessWidget {
  final InAppNotices notices;
  final VoidCallback onPressed;
  const NoticeBell({super.key, required this.notices, required this.onPressed});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: notices,
    builder: (context, _) => IconButton(
      tooltip: notices.unread == 0 ? '消息提醒' : '消息提醒 · ${notices.unread} 条未读',
      onPressed: onPressed,
      icon: Badge(
        isLabelVisible: notices.enabledAll && notices.unread > 0,
        label: Text('${notices.unread}'),
        child: const Icon(Icons.notifications_none_rounded),
      ),
    ),
  );
}

class NoticeOverlay extends StatefulWidget {
  final InAppNotices notices;
  final Widget child;
  const NoticeOverlay({super.key, required this.notices, required this.child});
  @override
  State<NoticeOverlay> createState() => _NoticeOverlayState();
}

class _NoticeOverlayState extends State<NoticeOverlay> {
  Timer? _hide;
  AppNotice? _shown;
  @override
  void initState() {
    super.initState();
    widget.notices.addListener(_changed);
  }

  void _changed() {
    final opened = widget.notices.opened;
    if (opened != null) {
      widget.notices.opened = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openNotice(context, opened);
      });
    }
    if (!mounted) return;
    final next = widget.notices.banner;
    if (!identical(_shown, next)) {
      _hide?.cancel();
      _shown = next;
      if (next != null) {
        _hide = Timer(const Duration(seconds: 7), () {
          if (mounted && identical(widget.notices.banner, next)) {
            widget.notices.dismiss();
          }
        });
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _hide?.cancel();
    widget.notices.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notice = widget.notices.banner;
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          Positioned.fill(child: widget.child),
          if (notice != null)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 68,
              right: 12,
              left: constraints.maxWidth < 650 ? 12 : null,
              width: constraints.maxWidth < 650 ? null : 420,
              child: Semantics(
                liveRegion: true,
                child: Material(
                  elevation: 8,
                  shadowColor: violet.withValues(alpha: .18),
                  color: Theme.of(context).colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: violet.withValues(alpha: .18)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => openNotice(context, notice),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                      child: Row(
                        children: [
                          IconBadge(noticeIcon(notice.kind), size: 38),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  notice.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  widget.notices.showPreview &&
                                          notice.preview.isNotEmpty
                                      ? notice.preview
                                      : '点击查看 · ${noticeKind(notice.kind)}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '关闭提醒横幅',
                            onPressed: widget.notices.dismiss,
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
