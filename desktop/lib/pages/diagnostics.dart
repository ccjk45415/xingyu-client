import 'package:flutter/material.dart';

import '../core/error_diagnostics.dart';
import '../ui/shared.dart';

Future<void> showDiagnostics(
  BuildContext context, {
  DiagnosticStore? store,
}) async {
  final diagnostics = store ?? appDiagnostics;
  await diagnostics.initialize();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: SizedBox(
          width: 860,
          height: MediaQuery.sizeOf(context).height * .8,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AnimatedBuilder(
              animation: diagnostics,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.bug_report_outlined,
                        color: violet,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          '诊断信息',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '遇到问题时，复制诊断发给开发者。只保存在本机，不会自动上传。',
                    style: TextStyle(color: Colors.grey, height: 1.6),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Scrollbar(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(18),
                          child: SelectableText(
                            diagnostics.report(),
                            style: const TextStyle(
                              fontFamily: 'Consolas',
                              fontFamilyFallback: [
                                'Microsoft YaHei UI',
                                'Microsoft YaHei',
                                'Segoe UI',
                              ],
                              fontSize: 12,
                              height: 1.7,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: () =>
                            copy(context, diagnostics.report(), '诊断已复制'),
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        label: const Text('复制诊断'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          if (await confirm(
                            context,
                            '清空本机异常记录？',
                            '只清除诊断记录，不影响账号、投稿草稿或阅读数据。',
                            action: '清空',
                          )) {
                            await diagnostics.clear();
                          }
                        },
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('清空记录'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
