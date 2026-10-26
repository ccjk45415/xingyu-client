import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/platform.dart';
import '../ui/shared.dart';

String cloudCheckinError(Object error) {
  if (error is ApiFailure) {
    return switch (error.status) {
      401 => '登录或云端授权已失效，请重新登录后开启',
      409 => '账号已切换，请在当前账号重新操作',
      429 => '云端签到尝试过于频繁，请稍后重试',
      502 => '签到服务暂时无法连接网站，请稍后重试',
      503 => '云端签到服务暂时不可用，请稍后重试',
      _ => '云端签到操作未完成，请刷新状态后重试',
    };
  }
  return '未能连接签到服务，请检查网络后刷新状态';
}

class CheckinCard extends StatelessWidget {
  const CheckinCard({super.key});
  @override
  Widget build(BuildContext context) {
    final app = stateOf(context), checkin = app.checkin;
    if (!app.clientConfig.enabled('checkin')) return const SizedBox.shrink();
    return Surface(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          IconBadge(
            checkin.signed
                ? Icons.event_available_rounded
                : Icons.calendar_month_rounded,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.clientConfig.label('checkin', '每日签到'),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  checkin.message.isNotEmpty
                      ? checkin.message
                      : checkin.signed
                      ? '今日已签到，明天再见'
                      : '收下一份今天的小奖励',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: checkin.busy ? null : () => action(context, checkin.run),
            child: Text(
              checkin.busy
                  ? '确认中'
                  : checkin.signed
                  ? '已签到'
                  : '签到',
            ),
          ),
          IconButton(
            tooltip: '签到设置',
            onPressed: () =>
                openRoute(context, const DeskRoute('checkin', '签到')),
            icon: const Icon(Icons.tune_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class CheckinPage extends StatefulWidget {
  const CheckinPage({super.key});
  @override
  State<CheckinPage> createState() => _CheckinPageState();
}

class _CheckinPageState extends State<CheckinPage> {
  String? cloudError;
  bool working = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(refresh());
    });
  }

  Future<void> refresh() async {
    try {
      await stateOf(context).checkin.refreshCloud();
      if (mounted) setState(() => cloudError = null);
    } catch (error) {
      if (mounted) setState(() => cloudError = cloudCheckinError(error));
    }
  }

  Future<void> cloud(bool enabled) async {
    final app = stateOf(context);
    if (enabled &&
        !await confirm(
          context,
          '开启云端自动签到？',
          '开启后，你的登录会话将单独加密保存在签到服务中，仅用于验证身份与每日签到，不保存密码。授权最长7天，过期或登录失效后需要重新开启。关闭后服务会删除会话；退出登录时会尝试关闭，离线时请稍后联网确认。服务端可能受到网站网络限制，无法保证每天成功。',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      working = true;
      cloudError = null;
    });
    try {
      await app.checkin.setCloud(enabled);
    } catch (error) {
      if (mounted) setState(() => cloudError = cloudCheckinError(error));
    }
    if (mounted) setState(() => working = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = stateOf(context), c = app.checkin;
    return PageBody(
      width: 850,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Heading('签到', '每天一份小奖励，按自己的节奏开启。'),
          const CheckinCard(),
          const SizedBox(height: 16),
          Surface(
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  secondary: const IconBadge(Icons.login_rounded),
                  title: const Text('打开应用自动签到'),
                  subtitle: Text(
                    isWindows
                        ? '登录、启动和回到窗口时立即检查，窗口打开时持续确认'
                        : '启动和回到应用时检查，已签到时不会重复领取',
                  ),
                  value: c.openEnabled,
                  onChanged: (v) =>
                      action(context, () => c.setPreference('on_open', v)),
                ),
                if (isAndroid) ...[
                  const Divider(height: 28),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    secondary: const IconBadge(
                      androidTestChannel
                          ? Icons.schedule_rounded
                          : Icons.history_rounded,
                    ),
                    title: const Text('后台自动签到'),
                    subtitle: Text(
                      number(c.background['period_minutes']) == 15
                          ? '约每15分钟由系统检查，临时失败会退避重试；需要保持登录和代理网络可用，省电限制仍可能延迟。'
                          : '约每3小时由系统安排尝试，需要保持登录与代理网络可用；强行停止或省电限制会影响执行。',
                    ),
                    value: c.backgroundEnabled,
                    onChanged: (v) =>
                        action(context, () => c.setPreference('background', v)),
                  ),
                  if (c.background.isNotEmpty)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('最近后台任务'),
                      subtitle: Text(
                        '${c.backgroundStatus}\n${text(c.background['time'])}',
                      ),
                    ),
                ],
                // Keep Android-only icon constants in their original branch:
                // desktop bases do not contain that tree-shaken glyph.
                if (isWindows) ...[
                  const Divider(height: 28),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    secondary: const IconBadge(Icons.history_rounded),
                    title: const Text('后台自动签到'),
                    subtitle: const Text(
                      '最小化到托盘后继续，每30秒确认官网状态；未签到时立即提交。完全退出、休眠或断网时无法执行。',
                    ),
                    value: c.backgroundEnabled,
                    onChanged: (v) =>
                        action(context, () => c.setPreference('background', v)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (app.clientConfig.enabled('cloud_checkin'))
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    secondary: const IconBadge(Icons.cloud_sync_rounded),
                    title: const Text('云端自动签到'),
                    subtitle: const Text('设备关机也能尝试执行 · 独立授权 · 7天有效'),
                    value: c.cloud['enabled'] == true,
                    onChanged: working ? null : cloud,
                  ),
                  if (text(c.cloud['expires_at']).isNotEmpty)
                    Text(
                      '授权到期：${dateText(c.cloud['expires_at'])}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  if (cloudError != null)
                    Text(
                      cloudError!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.deepOrange,
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: working ? null : refresh,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('刷新状态'),
                    ),
                  ),
                  for (final record in rows(c.cloud['history']))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        record['status'] == 'signed'
                            ? Icons.check_circle_outline_rounded
                            : Icons.info_outline_rounded,
                        color: violet,
                      ),
                      title: Text(
                        record['status'] == 'signed'
                            ? '今日已签到'
                            : record['status'] == 'expired'
                            ? '授权已过期，请重新开启'
                            : record['status'] == 'login_required'
                            ? '登录失效，请重新授权'
                            : '本次未完成，稍后重试',
                      ),
                      subtitle: Text(dateText(record['time'])),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
