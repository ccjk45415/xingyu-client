import 'cache_settings.dart';
import 'submission_workbench.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/comment_content.dart';
import '../core/media.dart';
import '../core/updates.dart';
import '../core/platform.dart';
import '../ui/shared.dart';
import 'discovery.dart';
import 'account_overview.dart';
import 'diagnostics.dart';
import 'checkin.dart';
import 'patch_updates.dart';

class AccountPage extends StatelessWidget {
  final DeskRoute route;
  const AccountPage(this.route, {super.key});
  @override
  Widget build(BuildContext context) {
    final app = stateOf(context);
    if (route.kind == 'checkin') return const CheckinPage();
    if (route.kind == 'settings' ||
        ['profile', 'security', 'appearance', 'updates'].contains(route.kind)) {
      return SettingsPage(route.kind == 'settings' ? '' : route.kind);
    }
    if (route.kind == 'notifications' || route.kind == 'myComments') {
      return SocialListPage(route);
    }
    if (route.kind == 'history') {
      return PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Heading('阅读足迹', '按账号保存在本机，只记录最近150篇作品。'),
            if (app.history.isEmpty)
              const Blank('还没有阅读足迹', '去发现页看看吧。')
            else
              PostGrid(app.history),
          ],
        ),
      );
    }
    if (route.kind == 'logs') {
      return AsyncPane(
        load: () =>
            app.get('user/creditLog', {'page': route.page, 'per_page': 20}),
        builder: (r, reload) => PageBody(
          width: 950,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Heading('积分与经验', '与官网账号同步'),
              for (final row in rows(r['data']))
                Card(
                  child: ListTile(
                    title: Text(
                      '积分 ${number(row['point'])}   ·   经验 ${number(row['exp'])}',
                    ),
                    subtitle: Text(
                      '${text(row['description'])}\n${dateText(row['created_at'])}',
                    ),
                  ),
                ),
              Pagination(r, route.page, (p) => openRoute(context, route.at(p))),
            ],
          ),
        ),
      );
    }
    return const AccountOverview();
  }
}

class SocialListPage extends StatelessWidget {
  final DeskRoute route;
  const SocialListPage(this.route, {super.key});
  @override
  Widget build(BuildContext context) {
    final app = stateOf(context),
        mine = route.kind == 'myComments',
        type = route.filter.isEmpty ? 'reply' : route.filter;
    return AsyncPane(
      load: () => app.get(
        mine
            ? 'user/comment'
            : type == 'system'
            ? 'announce/list'
            : 'user/notification',
        {
          'page': route.page,
          'per_page': 15,
          if (mine) ...{
            'id': app.uid,
            'include': 'post:simple,user',
            'with[0]': 'post',
            'with[1]': 'user',
          } else if (type != 'system') ...{
            'action': type,
            'include': 'user,causer,subject',
            'with[0]': 'user',
            'with[1]': 'causer',
            'with[2]': 'subject',
          },
        },
      ),
      builder: (r, reload) => PageBody(
        width: 1050,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Heading(
              mine ? '我的评论' : '通知',
              mine ? '管理自己发布的评论，继续参与讨论。' : '与你有关的每一次回应。',
              trailing: IconButton(
                tooltip: '刷新列表',
                onPressed: reload,
                icon: const Icon(Icons.refresh),
              ),
            ),
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  children: [
                    Wrap(
                      spacing: 12,
                      children: [
                        for (final e in {
                          'reply': '回复',
                          'vote': '点赞',
                          'system': '系统',
                        }.entries)
                          ChoiceChip(
                            label: Text(e.value),
                            selected: type == e.key,
                            onSelected: (_) => openRoute(
                              context,
                              DeskRoute('notifications', '通知', filter: e.key),
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        if (await confirm(
                              context,
                              '全部标为已读？',
                              '将同步更新官网中当前分类的通知状态。',
                            ) &&
                            context.mounted) {
                          await action(context, () async {
                            await app.post(
                              type == 'system'
                                  ? 'user/makeAnnounceAsRead'
                                  : 'user/makeNotificationAsRead',
                              type == 'system'
                                  ? {}
                                  : {'all': true, 'action': type},
                            );
                            reload();
                          });
                        }
                      },
                      child: const Text('全部已读'),
                    ),
                  ],
                ),
              ),
            if (rows(r['data']).isEmpty) const Blank('暂时没有内容', '新的互动会出现在这里。'),
            for (final n in rows(r['data']))
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Surface(child: _card(context, n, mine, type, reload)),
              ),
            Pagination(r, route.page, (p) => openRoute(context, route.at(p))),
          ],
        ),
      ),
    );
  }

  Widget _card(
    BuildContext context,
    Json n,
    bool mine,
    String type,
    VoidCallback reload,
  ) {
    final app = stateOf(context),
        actor = object(n['user']),
        subject = object(n['subject']),
        causer = object(n['causer']),
        post = object(n['post']);
    if (!mine && type == 'system') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text(n['title'], '系统公告'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            dateText(n['created_at']),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          RichContent(text(n['content']), fontSize: 15),
        ],
      );
    }
    final target = mine
        ? number(n['post_id'])
        : n['subject_type'] == 'post'
        ? number(subject['id'])
        : number(subject['post_id']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!mine)
          Row(
            children: [
              Avatar(
                actor,
                radius: 17,
                onTap: () => openRoute(
                  context,
                  DeskRoute('author', '作者主页', id: number(actor['id'])),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${n['read_at'] == null ? '● ' : ''}${text(actor['nickname'], '仓库用户')} ${type == 'vote' ? '赞了你的${n['subject_type'] == 'post' ? '作品' : '评论'}' : '回复了你的${n['subject_type'] == 'post' ? '作品' : '评论'}'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        if (mine)
          Text(
            text(post['title'], '原作品已删除或不可见'),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        const SizedBox(height: 12),
        Text(
          dateText(n['created_at']),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        RichContent(
          renderCommentContent(
            mine
                ? text(n['content'])
                : type == 'vote'
                ? text(subject['title'], text(subject['content']))
                : text(causer['content'], '原回复已删除或不可见'),
          ),
          fontSize: 15,
          maxImageHeight: 300,
          maxImageWidth: 480,
        ),
        if (!mine && type != 'vote' && subject.isNotEmpty) ...[
          const SizedBox(height: 10),
          Surface(
            padding: const EdgeInsets.all(14),
            color: violet.withValues(alpha: .06),
            child: RichContent(
              renderCommentContent(
                text(subject['title'], text(subject['content'])),
              ),
              fontSize: 13,
              maxImageHeight: 240,
              maxImageWidth: 420,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          children: [
            TextButton.icon(
              onPressed: target > 0
                  ? () => openRoute(
                      context,
                      DeskRoute('article', '作品详情', id: target),
                    )
                  : null,
              icon: const Icon(Icons.open_in_new, size: 15),
              label: const Text('查看作品与讨论'),
            ),
            if (mine && number(n['user_id']) == app.uid)
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
                      await app.post('comment/delete', {'id': n['id']});
                      reload();
                    });
                  }
                },
                child: const Text('删除'),
              ),
            if (!mine && n['read_at'] == null)
              TextButton(
                onPressed: () => action(context, () async {
                  await app.post('user/makeNotificationAsRead', {
                    'ids': [text(n['id'])],
                    'action': type,
                  });
                  reload();
                }),
                child: const Text('标为已读'),
              ),
          ],
        ),
      ],
    );
  }
}

class SettingsPage extends StatelessWidget {
  final String section;
  const SettingsPage(this.section, {super.key});
  @override
  Widget build(BuildContext context) {
    final app = stateOf(context);
    if (section == 'profile') return const ProfileForm();
    if (section == 'security') return const SecurityForm();
    if (section == 'appearance') {
      return PageBody(
        width: 900,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Heading('阅读与外观', '让星屿更贴近你的习惯。'),
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('深色模式'),
                    subtitle: const Text('适合夜间阅读的柔和深色背景'),
                    value: app.dark,
                    onChanged: app.setDark,
                  ),
                  const Divider(height: 24),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.dashboard_customize_outlined,
                      color: violet,
                    ),
                    title: const Text('分类页排版'),
                    subtitle: const Text('卡片漫游，或顶部一级 / 二级导航'),
                  ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('卡片排版'),
                        selected: !app.categoryTopNavigation,
                        onSelected: (_) => app.setCategoryLayout(false),
                      ),
                      ChoiceChip(
                        label: const Text('顶部双层导航'),
                        selected: app.categoryTopNavigation,
                        onSelected: (_) => app.setCategoryLayout(true),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  if (isWindows) ...[
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.desktop_windows_rounded,
                        color: violet,
                      ),
                      title: Text('窗口关闭方式'),
                      subtitle: Text('点击右上角 × 时的行为'),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: app.windowsCloseAction,
                      items: const [
                        DropdownMenuItem(value: 'ask', child: Text('每次询问')),
                        DropdownMenuItem(
                          value: 'tray',
                          child: Text('最小化到系统托盘'),
                        ),
                        DropdownMenuItem(value: 'exit', child: Text('退出程序')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          unawaited(app.setWindowsCloseAction(value));
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '托盘内可打开窗口、立即签到或退出。后台签到需在“签到设置”中开启。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const Divider(height: 32),
                  ],
                  Text(
                    '正文字号  ${app.fontSize.round()} px',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Slider(
                    min: 13,
                    max: 26,
                    divisions: 13,
                    value: app.fontSize,
                    onChanged: app.setFont,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '把每一种喜欢，都收藏在自己的小宇宙。',
                    style: TextStyle(fontSize: app.fontSize, height: 1.85),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    if (section == 'updates') {
      return PageBody(
        width: 900,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Heading(
              '检查更新',
              isAndroid
                  ? '仓库 · 星屿 Android 客户端'
                  : isMacOS
                  ? '仓库 · 星屿 macOS 客户端'
                  : '仓库 · 星屿 Windows 客户端',
            ),
            const PatchUpdatesCard(),
            const SizedBox(height: 16),
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_awesome, size: 44, color: violet),
                  const SizedBox(height: 20),
                  Text(
                    '星屿 $clientVersion',
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isAndroid
                        ? 'Flutter Android · ARM64\n沿用原版应用名称与签名，可覆盖安装。更新下载完成后自动打开系统安装程序。'
                        : isMacOS
                        ? 'Flutter Desktop · macOS Apple Silicon\n下载完成后自动打开 PKG 安装器，按系统提示安装。'
                        : 'Flutter Desktop · Windows x64\n自动下载并校验更新包，完成后替换程序、重新启动，失败时恢复旧版。',
                    style: const TextStyle(height: 1.8),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () =>
                        action(context, () => checkWindowsUpdate(context)),
                    icon: const Icon(Icons.system_update_alt, size: 18),
                    label: const Text('检查新版本'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return PageBody(
      width: 950,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Heading('设置', '账号与阅读偏好，都在这里。'),
          Surface(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
            child: Column(
              children: [
                for (final e in [
                  ('编辑个人资料', '昵称、简介、头像与背景', Icons.badge_outlined, 'profile'),
                  (
                    '网络与代理',
                    '系统代理、局域网 Clash 与补丁连接',
                    Icons.wifi_tethering_rounded,
                    'networkSettings',
                  ),
                  ('账号安全', '修改密码、更改绑定邮箱', Icons.shield_outlined, 'security'),
                  (
                    '通知设置',
                    '私信、艾特与回复的应用内提醒',
                    Icons.notifications_none_rounded,
                    'noticeSettings',
                  ),
                  (
                    '签到设置',
                    '打开应用、后台与云端签到',
                    Icons.event_available_rounded,
                    'checkin',
                  ),
                  (
                    '阅读与外观',
                    '主题、正文字号与分类页排版',
                    Icons.palette_outlined,
                    'appearance',
                  ),
                  (
                    '检查更新',
                    '当前版本 $clientVersion',
                    Icons.system_update_alt_outlined,
                    'updates',
                  ),
                ])
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    leading: IconBadge(e.$3),
                    title: Text(e.$1),
                    subtitle: Text(e.$2, style: const TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => openRoute(context, DeskRoute(e.$4, e.$1)),
                  ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 12,
                  ),
                  leading: const IconBadge(Icons.storage_rounded),
                  title: const Text('本地缓存'),
                  subtitle: const Text(
                    '缓存浏览内容、图片与清理空间',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showCacheSettings(context, app),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 12,
                  ),
                  leading: const IconBadge(Icons.tune_rounded),
                  title: const Text('个人投稿习惯'),
                  subtitle: const Text(
                    '正文字号、行高与段落间距',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showSubmissionWorkbench(
                    context,
                    app: app,
                    title: '',
                    body: '',
                    task: 'habits',
                  ),
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 12,
                  ),
                  leading: const IconBadge(Icons.bug_report_outlined),
                  title: const Text('诊断信息'),
                  subtitle: const Text(
                    '查看、复制和清空本机异常记录',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showDiagnostics(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 25),
          const Text(
            '非官方客户端 · 站点内容与账号服务由 cangku.moe 提供。\n聊天与私信使用仓库认证；官网会话仅临时用于核验，服务不保存密码或官网会话。',
            style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.9),
          ),
        ],
      ),
    );
  }
}

String uploadedUrl(Json result) {
  final data = object(result['data']);
  final raw = text(data['url'], text(data['link'], text(result['link'])));
  return raw.startsWith('/') ? '$siteOrigin$raw' : raw;
}

class ProfileForm extends StatelessWidget {
  const ProfileForm({super.key});
  @override
  Widget build(BuildContext context) => AsyncPane(
    load: () =>
        stateOf(context).get('auth/me', {'include': 'roles,permissions,meta'}),
    builder: (r, reload) => _ProfileFields(object(r['data'])),
  );
}

class _ProfileFields extends StatefulWidget {
  final Json user;
  const _ProfileFields(this.user);
  @override
  State<_ProfileFields> createState() => _ProfileFieldsState();
}

class _ProfileFieldsState extends State<_ProfileFields> {
  final Map<String, TextEditingController> fields = {};
  final Json original = {};
  String sex = 'secret', avatar = '', banner = '';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    final meta = widget.user['meta'] is List
        ? {
            for (final v in rows(widget.user['meta']))
              text(v['key']): v['value'],
          }
        : object(widget.user['meta']);
    for (final k in ['nickname', 'description', 'website', 'location']) {
      fields[k] = TextEditingController(
        text: text(widget.user[k], text(meta[k])),
      );
    }
    sex = text(widget.user['sex'], 'secret');
    avatar = text(widget.user['avatar']);
    banner = text(widget.user['banner']);
    original.addAll({
      for (final e in fields.entries) e.key: e.value.text,
      'sex': sex,
      'avatar': avatar,
      'banner': banner,
    });
  }

  @override
  void dispose() {
    for (final v in fields.values) {
      v.dispose();
    }
    super.dispose();
  }

  Future<void> upload(String type) async {
    if (busy) return;
    setState(() => busy = true);
    await action(context, () async {
      final bytes = await pickJpeg(context);
      if (bytes == null || !mounted) return;
      final result = await stateOf(context).site.upload(
        'user/uploadImage',
        type == 'avatar' ? 'avatar' : 'image',
        bytes,
        {'type': type},
      );
      final url = uploadedUrl(result);
      if (!safeExternal(url) || !url.startsWith('https:')) {
        throw ApiFailure(400, '网站未返回有效图片地址');
      }
      if (mounted) {
        setState(() {
          if (type == 'avatar') {
            avatar = url;
          } else {
            banner = url;
          }
        });
      }
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => PageBody(
    width: 900,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Heading('编辑个人资料', '保存后同步到官网，聊天昵称与头像也会更新。'),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Avatar({'avatar': avatar}, radius: 40),
                  const SizedBox(width: 25),
                  OutlinedButton(
                    onPressed: busy ? null : () => upload('avatar'),
                    child: const Text('上传头像'),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              for (final e in {
                'nickname': '昵称',
                'description': '个人简介',
                'website': '个人网站',
                'location': '所在地',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: TextField(
                    controller: fields[e.key],
                    enabled: !busy,
                    maxLength: e.key == 'nickname'
                        ? 30
                        : e.key == 'description'
                        ? 255
                        : null,
                    minLines: e.key == 'description' ? 3 : 1,
                    maxLines: e.key == 'description' ? 5 : 1,
                    decoration: InputDecoration(labelText: e.value),
                  ),
                ),
              DropdownButtonFormField<String>(
                initialValue:
                    [
                      'secret',
                      'male',
                      'female',
                      'otokonoko',
                      'futa',
                    ].contains(sex)
                    ? sex
                    : 'secret',
                decoration: const InputDecoration(labelText: '性别'),
                items: [
                  for (final e in {
                    'secret': '秘密',
                    'male': '男',
                    'female': '女',
                    'otokonoko': '伪娘',
                    'futa': '扶她',
                  }.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: busy ? null : (v) => sex = v ?? 'secret',
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Cover(banner, height: 160),
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: busy ? null : () => upload('banner'),
                child: const Text('上传空间背景'),
              ),
              const SizedBox(height: 27),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (fields['nickname']!.text.trim().isEmpty) {
                          message(context, '昵称不能为空');
                          return;
                        }
                        if (!await confirm(
                              context,
                              '保存个人资料？',
                              '昵称、简介和头像等变更将同步到官网。',
                            ) ||
                            !context.mounted) {
                          return;
                        }
                        setState(() => busy = true);
                        await action(context, () async {
                          final app = stateOf(context);
                          final values = <String, dynamic>{
                            'nickname': fields['nickname']!.text.trim(),
                            'description': fields['description']!.text,
                            'website': fields['website']!.text.trim(),
                            'location': fields['location']!.text,
                            'sex': sex,
                            'avatar': avatar,
                            'banner': banner,
                          };
                          final changes = {
                            for (final e in values.entries)
                              if (original[e.key] != e.value) e.key: e.value,
                          };
                          final website = text(values['website']);
                          if (website.isNotEmpty &&
                              (!safeExternal(website) ||
                                  ![
                                    'http',
                                    'https',
                                  ].contains(Uri.tryParse(website)?.scheme))) {
                            throw ApiFailure(400, '个人网站请填写有效的 HTTP/HTTPS 地址');
                          }
                          if (changes.isEmpty) return;
                          await app.post('user/update', {
                            'id': app.uid,
                            ...changes,
                          });
                          original.addAll(values);
                          try {
                            await app.refreshUser();
                          } catch (e) {
                            if (context.mounted) {
                              message(context, '资料已保存，聊天同步暂未完成：$e');
                            }
                          }
                        }, success: '个人资料已保存');
                        if (mounted) setState(() => busy = false);
                      },
                child: Text(busy ? '正在保存…' : '保存个人资料'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class SecurityForm extends StatefulWidget {
  const SecurityForm({super.key});
  @override
  State<SecurityForm> createState() => _SecurityFormState();
}

class _SecurityFormState extends State<SecurityForm> {
  final old = TextEditingController(),
      password = TextEditingController(),
      confirmPassword = TextEditingController(),
      emailPassword = TextEditingController(),
      email = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    for (final c in [old, password, confirmPassword, emailPassword, email]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageBody(
    width: 900,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Heading('账号安全', '更改后将清除本机登录，需要重新登录官网账号。'),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '修改密码',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              for (final e in [
                (old, '当前密码'),
                (password, '新密码'),
                (confirmPassword, '确认新密码'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: TextField(
                    controller: e.$1,
                    obscureText: true,
                    decoration: InputDecoration(labelText: e.$2),
                  ),
                ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (password.text.length < 6 ||
                            password.text != confirmPassword.text ||
                            old.text.isEmpty) {
                          message(context, '请填写当前密码，并确认两次新密码相同且至少6位');
                          return;
                        }
                        if (!await confirm(
                              context,
                              '更新账号密码？',
                              '成功后需要使用新密码重新登录。',
                            ) ||
                            !context.mounted) {
                          return;
                        }
                        setState(() => busy = true);
                        await action(context, () async {
                          final app = stateOf(context);
                          await app.post('user/updatePassword', {
                            'old_password': old.text,
                            'password': password.text,
                          });
                          old.clear();
                          password.clear();
                          confirmPassword.clear();
                          await app.logout();
                        }, success: '密码已更新，请重新登录');
                        if (mounted) setState(() => busy = false);
                      },
                child: const Text('更新密码'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '更改绑定邮箱',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: email,
                decoration: const InputDecoration(labelText: '新邮箱'),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: emailPassword,
                obscureText: true,
                decoration: const InputDecoration(labelText: '当前密码'),
              ),
              const SizedBox(height: 20),
              FilledButton.tonal(
                onPressed: busy
                    ? null
                    : () async {
                        if (!email.text.contains('@') ||
                            emailPassword.text.isEmpty) {
                          message(context, '请填写有效邮箱及当前密码');
                          return;
                        }
                        if (!await confirm(
                              context,
                              '更改绑定邮箱？',
                              '新邮箱：${email.text.trim()}\n可能需要重新验证邮箱。',
                            ) ||
                            !context.mounted) {
                          return;
                        }
                        setState(() => busy = true);
                        await action(context, () async {
                          final app = stateOf(context);
                          await app.post('user/updateEmail', {
                            'email': email.text.trim(),
                            'password': emailPassword.text,
                          });
                          emailPassword.clear();
                          email.clear();
                          await app.logout();
                        });
                        if (mounted) setState(() => busy = false);
                      },
                child: const Text('更改邮箱'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
