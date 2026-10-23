import 'package:flutter/material.dart';

import '../core/state.dart';
import '../core/submission_workbench.dart';
import 'shared.dart';
import 'ai_panels.dart';

Future<Set<int>?> showSubmissionCategories(
  BuildContext context,
  AppState app,
  Set<int> initial,
) => showDialog<Set<int>>(
  context: context,
  builder: (_) => _Categories(app, initial),
);

class _Categories extends StatefulWidget {
  final AppState app;
  final Set<int> initial;
  const _Categories(this.app, this.initial);
  @override
  State<_Categories> createState() => _CategoriesState();
}

class _CategoriesState extends State<_Categories> {
  late Set<int> selected = {...widget.initial};
  late final int owner = widget.app.uid;
  String query = '', error = '';
  bool busy = false;
  Future<void> refresh() async {
    setState(() {
      busy = true;
      error = '';
    });
    widget.app.refreshBrowsing();
    await widget.app.loadCategories();
    if (!mounted) return;
    setState(() {
      busy = false;
      if (widget.app.categories.isEmpty) error = '暂时无法获取分类，请联网后重试';
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = fullCategoryPaths(widget.app.categories),
        visible = all
            .where((p) => p.label.toLowerCase().contains(query.toLowerCase()))
            .toList();
    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      title: const Row(
        children: [
          IconBadge(Icons.account_tree_outlined),
          SizedBox(width: 12),
          Expanded(child: Text('完整投稿分类')),
        ],
      ),
      content: SizedBox(
        width: 680,
        height: MediaQuery.sizeOf(context).height * .6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              onChanged: (v) => setState(() => query = v),
              decoration: aiInput(
                '搜索分类',
                icon: Icons.search_rounded,
                hint: '分类名或完整路径',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '官网目录 ${all.length} 项 · 已选 ${selected.length} 项',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  onPressed: busy ? null : refresh,
                  tooltip: '刷新官网分类',
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            if (busy) const LinearProgressIndicator(),
            if (error.isNotEmpty) Text(error),
            if (visible.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('没有匹配的分类，请更换关键词或刷新目录'),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: visible.length,
                itemBuilder: (c, i) {
                  final entry = visible[i];
                  return CheckboxListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: Text(
                      entry.label,
                      style: const TextStyle(fontSize: 13),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    value: selected.contains(entry.id),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        selected.addAll(entry.ids);
                      } else {
                        selected.removeAll(
                          all
                              .where((p) => p.ids.contains(entry.id))
                              .map((p) => p.id),
                        );
                      }
                    }),
                  );
                },
              ),
            ),
            const Text(
              '选择子分类会自动带上父分类；所有分类都可以搜索，不受作品类型限制。',
              style: TextStyle(fontSize: 12, height: 1.6),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(selected.clear),
          child: const Text('清空'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: busy || all.isEmpty || owner != widget.app.uid
              ? null
              : () => Navigator.pop(
                  context,
                  selected.intersection(all.map((p) => p.id).toSet()),
                ),
          child: const Text('确认分类'),
        ),
      ],
    );
  }
}
