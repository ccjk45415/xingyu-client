import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/editor_hints.dart';
import '../core/editor_tools.dart';
import '../core/media.dart';
import '../core/reader.dart';
import '../core/state.dart';
import '../ui/shared.dart';
import 'account.dart';
import 'ai_assistant.dart';

const postStatuses = {
  'publish': '已发布',
  'future': '定时发布',
  'draft': '草稿',
  'pending': '待审核',
  'rejected': '已退回',
  'trash': '回收站',
};
String postFingerprint(Json post) {
  final categories = rows(
    post['categories'],
  ).map((v) => number(v['id'])).toList()..sort();
  final tags = rows(post['tags']).map((v) => text(v['name'])).toList()..sort();
  return sha256
      .convert(
        utf8.encode(
          jsonEncode([
            for (final key in [
              'title',
              'content',
              'thumb',
              'status',
              'created_at',
            ])
              post[key],
            categories,
            tags,
          ]),
        ),
      )
      .toString();
}

class AuthoringPage extends StatelessWidget {
  final DeskRoute route;
  const AuthoringPage(this.route, {super.key});
  @override
  Widget build(BuildContext context) {
    final app = stateOf(context),
        status = postStatuses.containsKey(route.filter)
            ? route.filter
            : 'publish';
    if (route.kind == 'editor') return PostEditor(route);
    if (route.kind == 'drafts') {
      return PageBody(
        width: 1000,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Heading('本机草稿', '仅保存在当前电脑，按仓库账号隔离，不会自动提交网站。'),
            if (app.drafts.isEmpty) const Blank('还没有本机草稿', '在投稿编辑器中输入后会自动保存。'),
            for (final e in app.drafts.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 15),
                child: Surface(
                  padding: const EdgeInsets.all(12),
                  child: ListTile(
                    leading: const Icon(
                      Icons.description_outlined,
                      color: violet,
                    ),
                    title: Text(text(object(e.value)['title'], '未命名草稿')),
                    subtitle: Text(
                      '本机保存 · ${dateText(object(e.value)['saved_at'])}',
                    ),
                    trailing: IconButton(
                      onPressed: () async {
                        if (await confirm(
                              context,
                              '删除本机草稿？',
                              '只删除这台电脑上的草稿，不改动网站投稿。',
                              action: '删除',
                            ) &&
                            context.mounted) {
                          await app.saveDraft(e.key, null);
                          if (context.mounted) {
                            openRoute(
                              context,
                              DeskRoute('drafts', '本机草稿', page: route.page + 1),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                    onTap: () => openRoute(
                      context,
                      DeskRoute(
                        'editor',
                        '继续编辑',
                        id: number(object(e.value)['id']),
                        query: e.key,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return AsyncPane(
      load: () => app.get('post/list', {
        'user_id': app.uid,
        'status': status,
        'page': route.page,
        'per_page': 15,
        'include': 'categories:simple,meta:include(reject_reason)',
        'simple': 1,
        if (route.query.isNotEmpty) 'search': route.query,
      }),
      builder: (result, reload) => PageBody(
        width: 1200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Heading(
              '投稿与管理',
              '属于你的作品，从灵感到发布。',
              trailing: FilledButton.icon(
                onPressed: () =>
                    openRoute(context, const DeskRoute('editor', '新建投稿')),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建投稿'),
              ),
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final e in postStatuses.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: e.key == status,
                    onSelected: (_) => openRoute(
                      context,
                      DeskRoute('manage', '投稿与管理', filter: e.key),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            TextFormField(
              initialValue: route.query,
              onFieldSubmitted: (s) => openRoute(
                context,
                DeskRoute('manage', '投稿与管理', filter: status, query: s.trim()),
              ),
              decoration: const InputDecoration(
                hintText: '搜索自己的投稿，按 Enter 查询',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 23),
            if (rows(result['data']).isEmpty)
              const Blank('这个状态下还没有投稿', '把灵感写下来，让新的故事开始。'),
            for (final post in rows(
              result['data'],
            ).where((p) => number(p['user_id']) == app.uid))
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Surface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 17,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.article_outlined, color: violet),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              text(post['title']),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              '${dateText(post['created_at'])}  ·  ${postStatuses[status]}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                            if (status == 'rejected')
                              Text(
                                '退回说明：${text(object(post['meta'])['reject_reason'], '请在编辑器或官网查看详细原因')}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 15),
                      if (status != 'trash')
                        TextButton(
                          onPressed: () => openRoute(
                            context,
                            DeskRoute('editor', '编辑投稿', id: number(post['id'])),
                          ),
                          child: const Text('编辑'),
                        ),
                      if (status == 'publish')
                        IconButton(
                          onPressed: () => openRoute(
                            context,
                            DeskRoute(
                              'article',
                              '作品详情',
                              id: number(post['id']),
                            ),
                          ),
                          tooltip: '查看作品',
                          icon: const Icon(Icons.open_in_new, size: 19),
                        ),
                      TextButton(
                        onPressed: () async {
                          if (!await confirm(
                                context,
                                status == 'trash' ? '恢复这篇投稿？' : '移入回收站？',
                                text(post['title']),
                              ) ||
                              !context.mounted) {
                            return;
                          }
                          await action(context, () async {
                            await app.post(
                              status == 'trash'
                                  ? 'post/restore'
                                  : 'post/delete',
                              {'id': post['id']},
                            );
                            reload();
                          }, success: '操作成功');
                        },
                        child: Text(status == 'trash' ? '恢复' : '回收站'),
                      ),
                    ],
                  ),
                ),
              ),
            Pagination(
              result,
              route.page,
              (p) => openRoute(context, route.at(p)),
            ),
          ],
        ),
      ),
    );
  }
}

class PostEditor extends StatefulWidget {
  final DeskRoute route;
  const PostEditor(this.route, {super.key});
  @override
  State<PostEditor> createState() => _PostEditorState();
}

class _PostEditorState extends State<PostEditor> {
  final title = TextEditingController(),
      content = TextEditingController(),
      thumb = TextEditingController(),
      tags = TextEditingController(),
      schedule = TextEditingController();
  final Set<int> categories = {};
  final contentFocus = FocusNode();
  EditorHistory? editHistory;
  bool applyingEdit = false;
  double sourceFontSize = 14;
  AppState? app;
  int owner = 0;
  String status = 'draft',
      oldStatus = 'draft',
      version = '',
      baseline = '',
      error = '';
  bool html = true,
      loading = true,
      busy = false,
      dirty = false,
      completed = false,
      preview = true;
  Timer? saveTimer;
  String get draftKey => widget.route.query.isNotEmpty
      ? widget.route.query
      : widget.route.id == 0
      ? 'new'
      : 'post.${widget.route.id}';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (app == null) {
      app = stateOf(context);
      owner = app!.uid;
      unawaited(load());
    }
  }

  Future<void> load() async {
    try {
      Json source = object(app!.drafts[draftKey]);
      if (source.isEmpty && widget.route.id > 0) {
        final p = object(
          (await app!.get('post/info', {
            'id': widget.route.id,
            'include': 'user,categories:simple,tags',
            'exclude_view': 1,
          }))['data'],
        );
        if (number(p['user_id']) != owner) throw ApiFailure(403, '只能编辑自己的投稿');
        source = {
          ...p,
          'baseline': postFingerprint(p),
          'version': p['updated_at'],
          'html': true,
          'category_ids': rows(p['categories']).map((c) => c['id']).toList(),
          'tag_text': rows(p['tags']).map((t) => text(t['name'])).join(', '),
          'oldStatus': p['status'],
          'schedule': siteTimestamp(text(p['created_at'])),
        };
      }
      if (!mounted || app!.uid != owner) return;
      title.text = text(source['title']);
      content.text = text(source['content']);
      thumb.text = text(source['thumb']);
      tags.text = text(source['tag_text']);
      schedule.text = text(source['schedule']);
      version = text(source['version']);
      baseline = text(source['baseline']);
      oldStatus = text(source['oldStatus'], 'draft');
      status = text(source['status'], 'draft');
      if (!['draft', 'pending', 'future', 'publish'].contains(status)) {
        status = 'pending';
      }
      categories.addAll((source['category_ids'] as List? ?? []).map(number));
      html = source['html'] != false;
      sourceFontSize =
          (number(source['editor_font_size']) == 0
                  ? 14
                  : number(source['editor_font_size']))
              .clamp(10, 28)
              .toDouble();
      editHistory = EditorHistory(captureEdit());
      for (final c in [title, thumb, tags, schedule]) {
        c.addListener(changed);
      }
      content.addListener(sourceChanged);
      setState(() => loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = '$e';
        });
      }
    }
  }

  Json snapshot() => {
    'id': widget.route.id,
    'owner': owner,
    'title': title.text,
    'content': content.text,
    'thumb': thumb.text,
    'tag_text': tags.text,
    'schedule': schedule.text,
    'status': status,
    'oldStatus': oldStatus,
    'html': html,
    'editor_font_size': sourceFontSize.toInt(),
    'category_ids': categories.toList(),
    'version': version,
    'baseline': baseline,
    'saved_at': DateTime.now().toIso8601String(),
  };
  void changed() {
    dirty = true;
    saveTimer?.cancel();
    saveTimer = Timer(
      const Duration(milliseconds: 650),
      () => unawaited(saveLocal()),
    );
    if (mounted) setState(() {});
  }

  Future<void> saveLocal() async {
    if (app == null || completed || !dirty) return;
    try {
      await app!.saveDraft(draftKey, snapshot(), owner: owner);
    } catch (e) {
      if (mounted) setState(() => error = '本机草稿未能保存：$e');
    }
  }

  @override
  void dispose() {
    saveTimer?.cancel();
    if (dirty && !completed && app != null) {
      unawaited(
        app!.saveDraft(draftKey, snapshot(), owner: owner).catchError((_) {}),
      );
    }
    contentFocus.dispose();
    for (final c in [title, content, thumb, tags, schedule]) {
      c.dispose();
    }
    super.dispose();
  }

  String bodyHtml() => html
      ? content.text
      : '<p>${const HtmlEscape().convert(content.text).replaceAll('\n', '<br>')}</p>';
  EditorSnapshot captureEdit() => EditorSnapshot(
    content.text,
    content.selection.isValid ? content.selection.start : content.text.length,
    content.selection.isValid ? content.selection.end : content.text.length,
    html: html,
  );
  void sourceChanged() {
    if (applyingEdit) return;
    final next = captureEdit(), old = editHistory?.current;
    editHistory?.record(next, typing: true);
    if (old?.text != next.text) {
      changed();
    } else if (mounted) {
      setState(() {});
    }
  }

  void renderEdit(EditorSnapshot next) {
    applyingEdit = true;
    html = next.html;
    content.value = TextEditingValue(
      text: next.text,
      selection: TextSelection(baseOffset: next.a, extentOffset: next.b),
    );
    applyingEdit = false;
    changed();
    contentFocus.requestFocus();
  }

  void applyEdit(EditorSnapshot next) {
    if (busy) return;
    if (next.text.length > 1000000) {
      message(context, '正文请控制在100万字符以内');
      return;
    }
    editHistory?.select(captureEdit());
    editHistory?.record(next);
    renderEdit(next);
  }

  void insert(String value) => applyEdit(insertMarkup(captureEdit(), value));
  void wrap(String before, String after, {String placeholder = '文字'}) =>
      applyEdit(
        wrapMarkup(captureEdit(), before, after, placeholder: placeholder),
      );
  void undoEdit(bool redo) {
    if (busy) return;
    editHistory?.select(captureEdit());
    final next = redo ? editHistory?.redo() : editHistory?.undo();
    if (next != null) renderEdit(next);
  }

  void editorZoom(int delta) {
    setState(() => sourceFontSize = (sourceFontSize + delta).clamp(10, 28));
    changed();
  }

  Future<void> chooseFontSize() async {
    final result = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('正文字号 · 应用于选区'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final size in [12, 14, 16, 18, 20, 24, 28, 32, 36, 48])
                  SizedBox(
                    width: 76,
                    child: TextButton(
                      onPressed: () => Navigator.pop(c, size),
                      child: Text('$size px'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      wrap(
        '<span style="font-size:${result}px">',
        '</span>',
        placeholder: '调整字号的文字',
      );
    }
  }

  Future<void> chooseColor(bool highlight) async {
    final result = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(highlight ? '文字背景色' : '文字颜色'),
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final hex in [
                  '#322c48',
                  '#8a6adb',
                  '#e797b7',
                  '#e05252',
                  '#e58b32',
                  '#9b8435',
                  '#3a926c',
                  '#278da0',
                  '#4078ce',
                  '#795aaf',
                  '#777777',
                  '#ffffff',
                ])
                  Tooltip(
                    message: hex,
                    child: InkWell(
                      onTap: () => Navigator.pop(c, hex),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Color(
                            int.parse(hex.substring(1), radix: 16) | 0xff000000,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      wrap(
        '<span style="${highlight ? 'background-color' : 'color'}:$result">',
        '</span>',
      );
    }
  }

  Future<void> insertLinkDialog({bool image = false}) async {
    final label = TextEditingController(text: '链接文字'),
        url = TextEditingController();
    String error = '';
    final result = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text(image ? '插入网络图片' : '插入链接'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: label,
                  maxLength: 200,
                  decoration: InputDecoration(
                    labelText: image ? '图片说明' : '显示文字',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: url,
                  maxLength: 3000,
                  decoration: InputDecoration(
                    labelText: image ? '图片 HTTP(S) 地址' : '链接地址',
                    errorText: error.isEmpty ? null : error,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final value = url.text.trim(),
                    uri = Uri.tryParse(url.text.trim());
                if (!safeExternal(value) ||
                    (image && !['http', 'https'].contains(uri?.scheme))) {
                  update(() => error = '请输入有效链接');
                  return;
                }
                final href = const HtmlEscape().convert(value),
                    name = const HtmlEscape().convert(label.text);
                Navigator.pop(
                  c,
                  image
                      ? '<p><img src="$href" alt="$name"></p>'
                      : '<a href="$href">$name</a>',
                );
              },
              child: const Text('插入'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    label.dispose();
    url.dispose();
    if (result != null && mounted) insert(result);
  }

  Future<void> findReplace() async {
    final find = TextEditingController(), replace = TextEditingController();
    String status = '仅修改当前本机正文，区分大小写';
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) {
          void run(String mode) {
            final needle = find.text;
            if (needle.isEmpty) {
              update(() => status = '请填写查找文字');
              return;
            }
            try {
              final v = captureEdit();
              if (mode == 'all') {
                final result = replaceEditorText(v.text, needle, replace.text);
                final count = needle.allMatches(v.text).length;
                applyEdit(EditorSnapshot(result, 0, 0, html: html));
                update(() => status = '已替换 $count 处，可使用撤销恢复');
                return;
              }
              if (mode == 'one' && v.text.substring(v.a, v.b) == needle) {
                final result = v.text.replaceRange(v.a, v.b, replace.text);
                applyEdit(
                  EditorSnapshot(
                    result,
                    v.a,
                    v.a + replace.text.length,
                    html: html,
                  ),
                );
                update(() => status = '已替换当前匹配');
                return;
              }
              var at = v.text.indexOf(needle, v.b);
              if (at < 0) at = v.text.indexOf(needle);
              if (at < 0) {
                update(() => status = '没有找到匹配内容');
                return;
              }
              content.selection = TextSelection(
                baseOffset: at,
                extentOffset: at + needle.length,
              );
              update(() => status = '已选中第 ${at + 1} 个字符处的匹配');
            } catch (e) {
              update(() => status = '$e');
            }
          }

          return AlertDialog(
            title: const Text('查找与替换'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: const Key('editor.find'),
                    controller: find,
                    maxLength: 300,
                    decoration: const InputDecoration(labelText: '查找文字'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('editor.replace'),
                    controller: replace,
                    maxLength: 2000,
                    decoration: const InputDecoration(labelText: '替换为'),
                  ),
                  const SizedBox(height: 12),
                  Text(status),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('关闭'),
              ),
              TextButton(
                onPressed: () => run('find'),
                child: const Text('查找下一个'),
              ),
              TextButton(
                onPressed: () => run('one'),
                child: const Text('替换当前'),
              ),
              FilledButton(
                onPressed: () => run('all'),
                child: const Text('全部替换'),
              ),
            ],
          );
        },
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    find.dispose();
    replace.dispose();
  }

  Widget tool(String label, IconData icon, VoidCallback? run) => IconButton(
    tooltip: label,
    onPressed: busy ? null : run,
    icon: Icon(icon, size: 21),
    style: IconButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
      minimumSize: const Size(40, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
    ),
  );
  Future<void> aiAssistant() async {
    if (busy) return;
    final app = stateOf(context), owner = stateOf(context).uid;
    final result = await showAiAssistant(context);
    if (!mounted || result == null || app.uid != owner) return;
    final nextBody = result.body
        ? (result.append && content.text.isNotEmpty
              ? '${content.text}\n${result.draft.body}'
              : result.draft.body)
        : null;
    if (nextBody != null && nextBody.length > 1000000) {
      message(context, '导入后超出编辑器容量，现有内容未修改');
      return;
    }
    if (result.title) title.text = result.draft.title;
    if (result.tags) tags.text = result.draft.tags.join(', ');
    if (result.cover && result.draft.cover.isNotEmpty) {
      thumb.text = result.draft.cover;
    }
    if (nextBody != null) {
      applyEdit(
        EditorSnapshot(nextBody, nextBody.length, nextBody.length, html: true),
      );
    }
    changed();
  }

  Widget toolbar() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 2,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          tool('AI 投稿助手', Icons.auto_awesome_outlined, aiAssistant),
          tool(
            '撤销',
            Icons.undo_rounded,
            editHistory?.canUndo == true ? () => undoEdit(false) : null,
          ),
          tool(
            '重做',
            Icons.redo_rounded,
            editHistory?.canRedo == true ? () => undoEdit(true) : null,
          ),
          tool(
            '加粗',
            Icons.format_bold,
            () => wrap('<strong>', '</strong>', placeholder: '加粗文字'),
          ),
          tool(
            '斜体',
            Icons.format_italic,
            () => wrap('<em>', '</em>', placeholder: '斜体文字'),
          ),
          tool('下划线', Icons.format_underlined, () => wrap('<u>', '</u>')),
          tool(
            '删除线',
            Icons.format_strikethrough,
            () => wrap('<del>', '</del>'),
          ),
          for (final size in [1, 2, 3])
            Tooltip(
              message: '$size级标题',
              child: IconButton(
                onPressed: busy
                    ? null
                    : () => wrap('<h$size>', '</h$size>', placeholder: '标题'),
                icon: Text(
                  'H$size',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                style: IconButton.styleFrom(minimumSize: const Size(40, 40)),
              ),
            ),
          tool(
            '段落',
            Icons.notes_rounded,
            () => wrap('<p>', '</p>', placeholder: '段落文字'),
          ),
          tool('插入换行', Icons.keyboard_return_rounded, () => insert('<br>')),
          tool(
            '无序列表',
            Icons.format_list_bulleted,
            () => applyEdit(listMarkup(captureEdit(), false)),
          ),
          tool(
            '有序列表',
            Icons.format_list_numbered,
            () => applyEdit(listMarkup(captureEdit(), true)),
          ),
          tool(
            '引用',
            Icons.format_quote_rounded,
            () => wrap('<blockquote>', '</blockquote>', placeholder: '引用文字'),
          ),
          tool('插入链接', Icons.link_rounded, insertLinkDialog),
          tool('上传正文图片', Icons.image_outlined, upload),
          tool(
            '插入网络图片',
            Icons.add_photo_alternate_outlined,
            () => insertLinkDialog(image: true),
          ),
          tool(
            '插入下载卡片模板',
            Icons.cloud_download_outlined,
            () => insert(htmlHints.last.code),
          ),
          tool(
            '插入表格',
            Icons.table_chart_outlined,
            () => insert(htmlHints[10].code),
          ),
          tool(
            '行内代码',
            Icons.code_rounded,
            () => wrap('<code>', '</code>', placeholder: 'code'),
          ),
          tool(
            '插入代码块',
            Icons.integration_instructions_outlined,
            showCodeDialog,
          ),
          tool(
            '水平分隔线',
            Icons.horizontal_rule_rounded,
            () => insert('\n<hr>\n'),
          ),
          tool('正文字号', Icons.format_size, chooseFontSize),
          tool('文字颜色', Icons.format_color_text, () => chooseColor(false)),
          tool('文字背景色', Icons.format_color_fill, () => chooseColor(true)),
          tool(
            '左对齐',
            Icons.format_align_left,
            () => wrap('<p style="text-align:left">', '</p>'),
          ),
          tool(
            '居中',
            Icons.format_align_center,
            () => wrap('<p style="text-align:center">', '</p>'),
          ),
          tool(
            '右对齐',
            Icons.format_align_right,
            () => wrap('<p style="text-align:right">', '</p>'),
          ),
          tool(
            '两端对齐',
            Icons.format_align_justify,
            () => wrap('<p style="text-align:justify">', '</p>'),
          ),
          tool('上标', Icons.superscript, () => wrap('<sup>', '</sup>')),
          tool('下标', Icons.subscript, () => wrap('<sub>', '</sub>')),
          tool(
            '增加缩进',
            Icons.format_indent_increase,
            () => applyEdit(indentSource(captureEdit(), false)),
          ),
          tool(
            '减少缩进',
            Icons.format_indent_decrease,
            () => applyEdit(indentSource(captureEdit(), true)),
          ),
          tool('清除选区格式', Icons.format_clear, () {
            if (captureEdit().a == captureEdit().b) {
              message(context, '请先选择需要清除格式的正文');
              return;
            }
            applyEdit(removeSelectionFormat(captureEdit()));
          }),
          tool(
            'HTML特殊字符',
            Icons.text_fields,
            () => insert('&lt;标签&gt; &amp; 文本'),
          ),
          tool('插入当前日期', Icons.today_outlined, () {
            final d = DateTime.now().toUtc().add(const Duration(hours: 8));
            insert(
              '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
            );
          }),
          tool('查找与替换', Icons.find_replace_rounded, findReplace),
          tool(
            '减小编辑字号',
            Icons.text_decrease,
            sourceFontSize > 10 ? () => editorZoom(-1) : null,
          ),
          tool(
            '增大编辑字号',
            Icons.text_increase,
            sourceFontSize < 28 ? () => editorZoom(1) : null,
          ),
        ],
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 12,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilterChip(
            label: const Text('HTML源码'),
            selected: html,
            onSelected: busy
                ? null
                : (v) {
                    if (!v && content.text.isNotEmpty) {
                      message(context, '已有正文时保留HTML排版，避免丢失格式');
                      return;
                    }
                    applyEdit(EditorSnapshot(content.text, 0, 0, html: v));
                  },
          ),
          FilterChip(
            label: const Text('实时预览'),
            selected: preview,
            onSelected: (v) => setState(() => preview = v),
          ),
          Text(
            '源码 ${content.text.runes.length} 字符 · 选中 ${captureEdit().b - captureEdit().a} · 编辑字号 ${sourceFontSize.toInt()}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    ],
  );

  Future<void> showCodeDialog() async {
    final code = TextEditingController();
    var language = 'cpp';
    String error = '';
    final result = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('插入代码块'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: language,
                    decoration: const InputDecoration(labelText: '代码语言'),
                    items: [
                      for (final e in codeLanguages.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) {
                      if (v != null) language = v;
                    },
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    key: const Key('editor.code'),
                    controller: code,
                    minLines: 8,
                    maxLines: 16,
                    maxLength: 100000,
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontFamilyFallback: ['Microsoft YaHei UI'],
                    ),
                    decoration: InputDecoration(
                      labelText: '粘贴代码',
                      hintText: '#include <iostream>\nint main() { return 0; }',
                      errorText: error.isEmpty ? null : error,
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
              onPressed: () {
                if (code.text.trim().isEmpty) {
                  update(() => error = '请先输入代码');
                  return;
                }
                Navigator.pop(c, codeBlock(language, code.text));
              },
              child: const Text('插入'),
            ),
          ],
        ),
      ),
    );
    // Dialog exit animation can retain the text field until the next frame.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    code.dispose();
    if (result != null && mounted) insert(result);
  }

  Future<void> upload({bool cover = false}) async {
    if (busy) return;
    setState(() => busy = true);
    await action(context, () async {
      final bytes = await pickJpeg(context);
      if (bytes == null || !mounted || app!.uid != owner) return;
      final result = await app!.site.upload('upload/image', 'image', bytes);
      final url = uploadedUrl(result);
      if (!url.startsWith('https:') || !safeExternal(url)) {
        throw ApiFailure(400, '上传结果未包含有效图片地址');
      }
      if (cover) {
        thumb.text = url;
      } else {
        insert(
          '<p><img src="${const HtmlEscape().convert(url)}" alt="图片"></p>',
        );
      }
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> selectCategories() async {
    if (app!.categories.isEmpty) await app!.loadCategories();
    if (!mounted) return;
    final selected = {...categories};
    final list = <Json>[];
    void flatten(List<Json> rows, String prefix) {
      for (final c in rows) {
        list.add({...c, '_label': '$prefix${text(c['name'])}'});
        flatten(rowsFrom(c['children']), '$prefix    ');
      }
    }

    flatten(app!.categories, '');
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('选择分类'),
          content: SizedBox(
            width: 450,
            height: 500,
            child: ListView(
              children: [
                for (final category in list)
                  CheckboxListTile(
                    value: selected.contains(number(category['id'])),
                    title: Text(text(category['_label'])),
                    onChanged: (v) => set(() {
                      if (v == true) {
                        selected.add(number(category['id']));
                      } else {
                        selected.remove(number(category['id']));
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    if (yes == true && mounted) {
      categories
        ..clear()
        ..addAll(selected);
      changed();
    }
  }

  List<Json> rowsFrom(dynamic value) => rows(value);
  Future<void> submit() async {
    if (busy) return;
    if (title.text.trim().isEmpty || content.text.trim().isEmpty) {
      message(context, '请填写标题与正文');
      return;
    }
    if (thumb.text.isNotEmpty &&
        (!thumb.text.startsWith('https:') || !safeExternal(thumb.text))) {
      message(context, '封面需为有效HTTPS图片地址');
      return;
    }
    if (status == 'future') {
      final when = DateTime.tryParse('${schedule.text.trim()}+08:00');
      if (when == null || !when.isAfter(DateTime.now())) {
        message(context, '定时时间需晚于现在，使用上海时间 YYYY-MM-DD HH:mm:ss');
        return;
      }
    }
    if (!await confirm(
          context,
          widget.route.id == 0 ? '提交这篇投稿？' : '保存网站上的投稿？',
          '${title.text.trim()}\n状态：${postStatuses[status]}${status == 'future' ? '\n上海时间：${schedule.text}' : ''}\n内容将同步到 cangku.moe。',
          action: '确认提交',
        ) ||
        !mounted) {
      return;
    }
    setState(() => busy = true);
    await saveLocal();
    try {
      if (app!.uid != owner) throw ApiFailure(409, '账号已切换');
      if (widget.route.id > 0) {
        final latest = object(
          (await app!.get('post/info', {
            'id': widget.route.id,
            'include': 'user,categories:simple,tags',
            'exclude_view': 1,
          }))['data'],
        );
        if (number(latest['user_id']) != owner) {
          throw ApiFailure(403, '只能修改自己的投稿');
        }
        if (version.isEmpty ||
            baseline.isEmpty ||
            text(latest['updated_at']) != version ||
            postFingerprint(latest) != baseline) {
          throw ApiFailure(409, '网站内容已在别处变更。请保留本机草稿，重新载入官网最新版本后再编辑。');
        }
        await app!.post('post/editLock/refresh', {'id': widget.route.id});
      }
      final payload = <String, dynamic>{
        'title': title.text.trim(),
        'content': bodyHtml(),
        'thumb': thumb.text.trim(),
        'tags': tags.text
            .split(RegExp('[,，]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toSet()
            .take(20)
            .toList(),
        'categories': categories.toList(),
        if (widget.route.id > 0) 'id': widget.route.id,
        if (oldStatus != 'rejected') 'status': status,
        if (status == 'future') 'created_at': schedule.text.trim(),
      };
      await app!.post(
        widget.route.id == 0
            ? 'post/create'
            : oldStatus == 'rejected'
            ? 'post/review'
            : 'post/update',
        payload,
      );
      completed = true;
      dirty = false;
      await app!.saveDraft(draftKey, null, owner: owner);
      if (mounted) {
        message(context, '投稿已同步到网站');
        openRoute(
          context,
          DeskRoute(
            'manage',
            '投稿与管理',
            filter: oldStatus == 'rejected' ? 'pending' : status,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e\n内容已保存在本机。若提交超时，请先核实管理列表，避免重复提交。');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (error.isNotEmpty && content.text.isEmpty && widget.route.id > 0) {
      return Blank('无法载入这篇投稿', error);
    }
    final canPublish = rows(app!.user?['permissions'])
        .any((p) => p['name'] == 'publish_posts');
    final statuses = {
      'draft': '云端草稿',
      'pending': '提交审核',
      if (canPublish) 'publish': '发布',
      if (canPublish) 'future': '定时发布',
      if (!canPublish && !['draft', 'pending'].contains(status))
        status: postStatuses[status] ?? status,
    };
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            unawaited(saveLocal()),
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
            unawaited(submit()),
      },
      child: PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Heading(
              widget.route.id == 0 ? '写下新的故事' : '继续你的创作',
              '本机草稿自动保存 · Ctrl+S 保存本机 · Ctrl+Enter 提交确认',
              trailing: FilledButton.icon(
                onPressed: busy ? null : submit,
                icon: const Icon(Icons.publish_outlined, size: 18),
                label: Text(busy ? '正在处理…' : '提交到网站'),
              ),
            ),
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Text(
                  error,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    height: 1.7,
                  ),
                ),
              ),
            TextField(
              controller: title,
              enabled: !busy,
              maxLength: 150,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(hintText: '一个吸引人的标题…'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    initialValue: statuses.containsKey(status)
                        ? status
                        : 'pending',
                    items: [
                      for (final e in statuses.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: busy
                        ? null
                        : (v) {
                            status = v ?? 'draft';
                            changed();
                          },
                    decoration: const InputDecoration(labelText: '投稿状态'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : selectCategories,
                  icon: const Icon(Icons.interests_outlined, size: 17),
                  label: Text('分类 · ${categories.length}'),
                ),
                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: tags,
                    enabled: !busy,
                    decoration: const InputDecoration(labelText: '标签，以逗号分隔'),
                  ),
                ),
                if (status == 'future')
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: schedule,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        labelText: '上海时间 YYYY-MM-DD HH:mm:ss',
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: thumb,
                    enabled: !busy,
                    decoration: const InputDecoration(
                      labelText: '封面图片 HTTPS 地址',
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                OutlinedButton(
                  onPressed: busy ? null : () => upload(cover: true),
                  child: const Text('上传封面'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Surface(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  toolbar(),
                  const Divider(height: 30),
                  LayoutBuilder(
                    builder: (c, size) {
                      final editor = CallbackShortcuts(
                            bindings: {
                              const SingleActivator(
                                LogicalKeyboardKey.keyB,
                                control: true,
                              ): () =>
                                  wrap('<strong>', '</strong>'),
                              const SingleActivator(
                                LogicalKeyboardKey.keyI,
                                control: true,
                              ): () =>
                                  wrap('<em>', '</em>'),
                              const SingleActivator(
                                LogicalKeyboardKey.keyU,
                                control: true,
                              ): () =>
                                  wrap('<u>', '</u>'),
                              const SingleActivator(
                                LogicalKeyboardKey.keyZ,
                                control: true,
                              ): () =>
                                  undoEdit(false),
                              const SingleActivator(
                                LogicalKeyboardKey.keyZ,
                                control: true,
                                shift: true,
                              ): () =>
                                  undoEdit(true),
                              const SingleActivator(
                                LogicalKeyboardKey.keyF,
                                control: true,
                              ): findReplace,
                            },
                            child: TextField(
                              key: const Key('editor.content'),
                              controller: content,
                              focusNode: contentFocus,
                              enabled: !busy,
                              minLines: 21,
                              maxLines: 45,
                              style: TextStyle(
                                fontSize: sourceFontSize,
                                height: 1.8,
                                fontFamily: 'Consolas',
                                fontFamilyFallback: [
                                  'Microsoft YaHei UI',
                                  'Microsoft YaHei',
                                ],
                              ),
                              decoration: const InputDecoration(
                                hintText: '从这里开始，把灵感变成作品…',
                                fillColor: Colors.transparent,
                              ),
                            ),
                          ),
                          rendered = Surface(
                            padding: const EdgeInsets.all(22),
                            color: violet.withValues(alpha: .035),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  '本机预览',
                                  style: TextStyle(fontSize: 11, color: violet),
                                ),
                                const SizedBox(height: 15),
                                RichContent(
                                  ReaderDocument.parse(bodyHtml()).content,
                                  fontSize: 15,
                                ),
                              ],
                            ),
                          );
                      if (preview && size.maxWidth > 1000) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: editor),
                            const SizedBox(width: 20),
                            Expanded(child: rendered),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          editor,
                          if (preview) ...[
                            const SizedBox(height: 20),
                            rendered,
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '草稿只保存在当前电脑。上传图片和提交投稿都会写入网站，提交前请确认内容与权限。',
              style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.8),
            ),
            const SizedBox(height: 25),
          ],
        ),
      ),
    );
  }
}
