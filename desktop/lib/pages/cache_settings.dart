import 'package:flutter/material.dart';

import '../core/browse_cache.dart';
import '../core/state.dart';
import '../ui/ai_panels.dart';
import '../ui/shared.dart';

Future<void> showCacheSettings(BuildContext context, AppState app) =>
    showDialog<void>(context: context, builder: (_) => CacheSettings(app));

class CacheSettings extends StatefulWidget {
  final AppState app;
  const CacheSettings(this.app, {super.key});
  @override
  State<CacheSettings> createState() => _CacheSettingsState();
}

class _CacheSettingsState extends State<CacheSettings> {
  late Future<({int bytes, int entries})> stats = BrowseCache.shared.size();
  bool busy = false;
  String result = '';
  Future<void> clear() async {
    final yes = await confirm(
      context,
      '清理浏览缓存？',
      '将删除已缓存的作品页面、列表、公开来源资料与图片。本机草稿、账号和投稿习惯会保留。',
      action: '清理',
    );
    if (!yes || !mounted) return;
    setState(() => busy = true);
    try {
      await BrowseCache.shared.clear();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      widget.app.followingFeed.clear();
      widget.app.authorCache.clear();
      if (mounted) {
        setState(() {
          stats = BrowseCache.shared.size();
          result = '浏览缓存已清理';
        });
      }
    } catch (_) {
      if (mounted) setState(() => result = '部分缓存暂时无法清理，请稍后重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.all(16),
    title: const Row(
      children: [
        IconBadge(Icons.storage_rounded),
        SizedBox(width: 12),
        Expanded(child: Text('本地缓存')),
      ],
    ),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            FutureBuilder<({int bytes, int entries})>(
              future: stats,
              builder: (c, snapshot) => Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: violet.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.offline_bolt_outlined,
                      size: 38,
                      color: violet,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      snapshot.hasData
                          ? '${(snapshot.data!.bytes / 1024 / 1024).toStringAsFixed(1)} MB'
                          : '正在统计…',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      snapshot.hasData
                          ? '${snapshot.data!.entries} 个缓存项目'
                          : '本机浏览资料',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('缓存浏览内容与图片'),
              subtitle: const Text('再次浏览优先读取本机，减少重复加载'),
              value: BrowseCache.shared.enabled,
              onChanged: busy
                  ? null
                  : (v) async {
                      await widget.app.setCacheEnabled(v);
                      if (mounted) setState(() {});
                    },
            ),
            const AiNotice(
              '最多保留约 192 MB、1800 项，超过容量或 30 天会自动淘汰。作品页面缓存短时复用，可手动刷新获取最新内容；网络失败时尝试读取旧缓存。私信、聊天和账号安全资料不进入浏览缓存。',
              icon: Icons.inventory_2_outlined,
            ),
            if (result.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(result),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: busy ? null : clear, child: const Text('清理缓存')),
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('完成'),
      ),
    ],
  );
}
