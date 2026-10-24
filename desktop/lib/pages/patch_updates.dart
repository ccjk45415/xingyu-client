import 'package:flutter/material.dart';

import '../ui/shared.dart';

class PatchUpdatesCard extends StatelessWidget {
  const PatchUpdatesCard({super.key});
  @override
  Widget build(BuildContext context) {
    final app = stateOf(context),
        patches = app.patches,
        config = app.clientConfig;
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: IconBadge(Icons.bolt_rounded),
            title: Text('静默更新'),
            subtitle: Text('补丁在后台下载，完全退出并重新打开应用后生效'),
          ),
          Text(
            patches.message,
            style: const TextStyle(fontSize: 13, color: violet),
          ),
          const SizedBox(height: 8),
          Text(
            '当前补丁 ${patches.current} · 更新通道 ${patches.track.name}\n在线配置 ${config.revision == 0 ? '内置默认' : '第 ${config.revision} 版'}',
            style: const TextStyle(
              fontSize: 12,
              height: 1.7,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '公告、发现和受支持的布局配置可直接刷新。新增系统能力、权限或包内资源时仍需安装新版。',
            style: TextStyle(fontSize: 12, height: 1.7),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: patches.busy || config.loading
                  ? null
                  : () async {
                      await Future.wait([
                        patches.check(force: true),
                        config.refresh(force: true),
                      ]);
                    },
              icon: const Icon(Icons.sync_rounded, size: 18),
              label: const Text('检查补丁与在线配置'),
            ),
          ),
        ],
      ),
    );
  }
}
