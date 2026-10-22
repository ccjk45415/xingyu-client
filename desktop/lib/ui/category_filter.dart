import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/category_preferences.dart';
import 'shared.dart';

Future<void> showHomeCategoryFilter(BuildContext context) async {
  final app = stateOf(context), owner = stateOf(context).uid;
  if (app.categories.isEmpty) await app.loadCategories();
  if (!context.mounted || app.uid != owner) return;
  final all = categoryNodes(app.categories)
      .map((c) => number(c['id']))
      .where((id) => id > 0)
      .toSet();
  final selected = app.homeCategories == null
      ? {...all}
      : effectiveCategories(app.homeCategories!, app.categories);
  final result = await showDialog<Set<int>>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, change) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.tune_rounded, color: violet),
            SizedBox(width: 10),
            Text('定制首页'),
          ],
        ),
        content: SizedBox(
          width: 660,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(c).height * .62,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '只看勾选的分类。设置按账号保存在这台设备，分类页和排行不受影响。',
                  style: TextStyle(fontSize: 13, height: 1.6),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => change(() => selected.addAll(all)),
                      icon: const Icon(Icons.done_all, size: 18),
                      label: const Text('全部分类'),
                    ),
                    TextButton(
                      onPressed: () => change(selected.clear),
                      child: const Text('清空选择'),
                    ),
                  ],
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        if (all.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('分类目录暂不可用，请联网后重试'),
                          ),
                        for (final root in app.categories)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Surface(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    tristate: true,
                                    value:
                                        selected.containsAll(
                                          categoryBranch(root),
                                        )
                                        ? true
                                        : categoryBranch(root)
                                              .any(selected.contains)
                                        ? null
                                        : false,
                                    title: Text(
                                      text(root['name']),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    onChanged: (_) => change(
                                      () => toggleCategory(
                                        selected,
                                        root,
                                        !selected.containsAll(
                                          categoryBranch(root),
                                        ),
                                        app.categories,
                                      ),
                                    ),
                                  ),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      for (final sub in categoryNodes(
                                        rows(root['children']),
                                      ))
                                        FilterChip(
                                          label: Text(text(sub['name'])),
                                          selected: selected.contains(
                                            number(sub['id']),
                                          ),
                                          onSelected: (v) => change(
                                            () => toggleCategory(
                                              selected,
                                              sub,
                                              v,
                                              app.categories,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    selected.isEmpty
                        ? '未勾选分类，首页将不显示作品'
                        : '已选 ${selected.length} 个分类',
                    style: const TextStyle(fontSize: 12, color: violet),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: all.isEmpty
                ? null
                : () => Navigator.pop(c, {...selected}),
            child: const Text('保存筛选'),
          ),
        ],
      ),
    ),
  );
  if (result != null && context.mounted && app.uid == owner) {
    await app.setHomeCategories(result.containsAll(all) ? null : result);
    if (context.mounted) openRoute(context, const DeskRoute('home', '发现'));
  }
}

class HomeFilterBar extends StatelessWidget {
  const HomeFilterBar({super.key});
  @override
  Widget build(BuildContext context) {
    final app = stateOf(context);
    final selected = app.homeCategories;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Surface(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.tune_rounded, color: violet, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '你的兴趣，由你决定',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    selected == null
                        ? '正在浏览全部分类'
                        : selected.isEmpty
                        ? '未勾选分类'
                        : '仅显示已选的 ${selected.length} 个分类',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => showHomeCategoryFilter(context),
              icon: const Icon(Icons.filter_list_rounded, size: 18),
              label: const Text('筛选'),
            ),
          ],
        ),
      ),
    );
  }
}
