import '../core/submission_workbench.dart';
import 'submission_workbench.dart';
import '../ui/submission_categories.dart';

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/editor_hints.dart';
import '../core/editor_tools.dart';
import '../core/editor_export.dart';
import '../core/visual_editor.dart';
import '../core/editor_links.dart';
import '../core/submission_guidance.dart';
import '../core/submission_extras.dart';
import '../ui/editor_ime_anchor.dart';
import '../ui/editor_templates.dart';
import '../core/media.dart';
import '../core/reader.dart';
import '../core/state.dart';
import '../core/platform.dart';
import '../ui/shared.dart';
import 'account.dart';
import 'ai_assistant.dart';
import 'editor_extras.dart';

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
            const Heading('本机草稿', '仅保存在本机，按仓库账号隔离，不会自动提交网站。'),
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
                              '只删除本机草稿，不改动网站投稿。',
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: violet.withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              status == 'draft'
                                  ? Icons.edit_note_rounded
                                  : Icons.article_rounded,
                              color: violet,
                            ),
                          ),
                          const SizedBox(width: 14),
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
                                const SizedBox(height: 8),
                                Text(
                                  '${dateText(post['created_at'])}  ·  ${postStatuses[status]}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (status == 'rejected')
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            '退回说明：${text(object(post['meta'])['reject_reason'], '请在编辑器或官网查看详细原因')}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          if (status != 'trash')
                            FilledButton.tonalIcon(
                              key: ValueKey('post.view.${post['id']}'),
                              onPressed: () => openRoute(
                                context,
                                DeskRoute(
                                  'article',
                                  status == 'draft' ? '草稿预览' : '作品详情',
                                  id: number(post['id']),
                                  filter: status == 'publish'
                                      ? ''
                                      : 'private-preview',
                                ),
                              ),
                              icon: Icon(
                                status == 'draft'
                                    ? Icons.preview_rounded
                                    : Icons.visibility_rounded,
                                size: 20,
                              ),
                              label: Text(status == 'draft' ? '查看草稿' : '查看作品'),
                            ),
                          if (status != 'trash')
                            OutlinedButton.icon(
                              onPressed: () => openRoute(
                                context,
                                DeskRoute(
                                  'editor',
                                  '编辑投稿',
                                  id: number(post['id']),
                                ),
                              ),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('编辑'),
                            ),
                          TextButton.icon(
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
                            icon: Icon(
                              status == 'trash'
                                  ? Icons.restore_rounded
                                  : Icons.delete_outline_rounded,
                              size: 18,
                            ),
                            label: Text(status == 'trash' ? '恢复' : '回收站'),
                          ),
                        ],
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
  final Future<Uint8List?> Function(BuildContext)? imagePicker;
  const PostEditor(this.route, {super.key, this.imagePicker});
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
  final previewScroll = ScrollController();
  final visual = VisualHtmlController();
  EditorHistory? editHistory;
  bool applyingEdit = false;
  bool focusedEditor = false;
  double sourceFontSize = 14;
  AppState? app;
  int owner = 0;
  String guideKind = 'other';
  bool guideAiImages = false;
  List<Json> sourceMaterials = [];
  String status = 'draft',
      oldStatus = 'draft',
      version = '',
      baseline = '',
      error = '';
  bool html = false,
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
      final savedBody = text(source['content']);
      // Legacy html=false drafts contained plain text. Current drafts always
      // store canonical HTML; visual/source is only an editor preference.
      content.text = savedBody;
      if (source['content_format'] != 'html' && source['html'] == false) {
        content.text = EditorSnapshot(
          savedBody,
          0,
          0,
          html: false,
        ).asHtml().text;
      }
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
      html = source['editor_mode'] == 'source';
      guideKind = text(source['guide_kind'], 'other');
      guideAiImages = source['guide_ai_images'] == true;
      sourceMaterials = rows(source['source_materials']);
      visual.load(content.text);
      visual.onSourceChanged = visualChanged;
      visual.onEditError = (error) {
        if (mounted) message(context, error);
      };
      visual.onImageEdit = (start, end, markup) =>
          unawaited(editImageAtom(start, end, markup));
      visual.onComponentEdit = (start, end, markup) =>
          unawaited(editComponent(start, end, markup));
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
    'content_format': 'html',
    'editor_mode': html ? 'source' : 'visual',
    'guide_kind': guideKind,
    'guide_ai_images': guideAiImages,
    'source_materials': sourceMaterials,
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
    previewScroll.dispose();
    visual.dispose();
    for (final c in [title, content, thumb, tags, schedule]) {
      c.dispose();
    }
    super.dispose();
  }

  String bodyHtml() => removeEmptyListPlaceholders(content.text);
  EditorSnapshot captureEdit() => EditorSnapshot(
    content.text,
    !html && visual.selection.isValid
        ? visual.sourceOffset(visual.selection.start)
        : content.selection.isValid
        ? content.selection.start
        : content.text.length,
    !html && visual.selection.isValid
        ? visual.sourceOffset(visual.selection.end)
        : content.selection.isValid
        ? content.selection.end
        : content.text.length,
  );
  void visualChanged() {
    if (applyingEdit || busy) return;
    applyingEdit = true;
    content.value = TextEditingValue(
      text: visual.source,
      selection: TextSelection(
        baseOffset: visual.sourceOffset(visual.selection.baseOffset),
        extentOffset: visual.sourceOffset(visual.selection.extentOffset),
      ),
    );
    applyingEdit = false;
    editHistory?.record(captureEdit(), typing: true);
    changed();
  }

  void sourceChanged() {
    if (applyingEdit) return;
    if (content.text.length > 1000000) {
      applyingEdit = true;
      content.value = TextEditingValue(
        text: visual.source,
        selection: const TextSelection.collapsed(offset: 0),
      );
      applyingEdit = false;
      message(context, '正文请控制在100万字符以内，已保留修改前的内容');
      return;
    }
    if (html && visual.source != content.text) {
      visual.load(
        content.text,
        start: content.selection.start,
        end: content.selection.end,
      );
    }
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
    content.value = TextEditingValue(
      text: next.text,
      selection: TextSelection(baseOffset: next.a, extentOffset: next.b),
    );
    visual.load(next.text, start: next.a, end: next.b);
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
    final selection = captureEdit();
    final existing = image || html
        ? null
        : EditorLink.at(selection.text, selection.a, selection.b);
    final selectedText = !html && visual.selection.isValid
        ? visual.text.substring(visual.selection.start, visual.selection.end)
        : '';
    final label = TextEditingController(
          text:
              existing?.label ?? (selectedText.isEmpty ? '链接文字' : selectedText),
        ),
        url = TextEditingController(text: existing?.url ?? '');
    String error = '';
    final route = DialogRoute<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text(
            image
                ? '插入网络图片'
                : existing == null
                ? '插入链接'
                : '编辑链接',
          ),
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
            if (existing != null)
              TextButton(
                onPressed: () => Navigator.pop(
                  c,
                  existing.update(
                    selection.text,
                    existing.label,
                    existing.url,
                    remove: true,
                  ),
                ),
                child: const Text('移除链接'),
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
                if (!image && label.text.isEmpty) {
                  update(() => error = '请输入链接文字');
                  return;
                }
                final href = const HtmlEscape().convert(value),
                    name = const HtmlEscape().convert(label.text);
                Navigator.pop(
                  c,
                  existing != null
                      ? existing.update(selection.text, label.text, value)
                      : image
                      ? '<p><img src="$href" alt="$name"></p>'
                      : '<a href="$href">$name</a>',
                );
              },
              child: Text(existing == null ? '插入' : '保存'),
            ),
          ],
        ),
      ),
    );
    final result = await Navigator.of(context).push(route);
    await route.completed;
    label.dispose();
    url.dispose();
    if (result != null && mounted) {
      if (content.text != selection.text) {
        message(context, '正文已变化，请重新选择链接');
        return;
      }
      if (existing != null) {
        applyEdit(EditorSnapshot(result, existing.start, existing.start));
      } else {
        renderEdit(selection);
        insert(result);
      }
    }
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
              if (!html) {
                final plain = visual.text;
                final selection = visual.selection;
                if (mode == 'all') {
                  replaceEditorText(
                    plain,
                    needle,
                    replace.text,
                  ); // allocation bound
                  final positions = needle
                      .allMatches(plain)
                      .map((m) => m.start)
                      .toList();
                  final draft = VisualHtmlController()..load(content.text);
                  for (final at in positions.reversed) {
                    draft.value = TextEditingValue(
                      text: draft.text.replaceRange(
                        at,
                        at + needle.length,
                        replace.text,
                      ),
                      selection: TextSelection.collapsed(
                        offset: at + replace.text.length,
                      ),
                    );
                  }
                  applyEdit(EditorSnapshot(draft.source, 0, 0));
                  draft.dispose();
                  update(() => status = '已替换 ${positions.length} 处，可使用撤销恢复');
                  return;
                }
                final from = selection.isValid ? selection.start : 0;
                final to = selection.isValid ? selection.end : 0;
                if (mode == 'one' && plain.substring(from, to) == needle) {
                  visual.value = TextEditingValue(
                    text: plain.replaceRange(from, to, replace.text),
                    selection: TextSelection(
                      baseOffset: from,
                      extentOffset: from + replace.text.length,
                    ),
                  );
                  update(() => status = '已替换当前匹配');
                  return;
                }
                var at = plain.indexOf(needle, to);
                if (at < 0) at = plain.indexOf(needle);
                if (at < 0) {
                  update(() => status = '没有找到匹配内容');
                  return;
                }
                visual.selection = TextSelection(
                  baseOffset: at,
                  extentOffset: at + needle.length,
                );
                update(() => status = '已选中第 ${at + 1} 个字符处的匹配');
                return;
              }
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
    final before = content.text, selected = captureEdit();
    final result = await showAiAssistant(
      context,
      editorTitle: title.text,
      editorBody: before,
      editorCover: thumb.text,
      editorKind: guideKind,
      editorAiImages: guideAiImages,
      editorSources: sourceMaterials,
      editorCategories: {...categories},
      selection: selected,
      postId: widget.route.id,
      proofPicker: widget.imagePicker,
    );
    if (!mounted || result == null || app.uid != owner) return;
    if (content.text != before) {
      message(context, '正文已变化，请重新打开助手，当前内容已保留');
      return;
    }
    if (result.editingExisting) {
      sourceMaterials = rows(result.draft.data['source_materials']);
      if (result.draft.body != before) {
        applyEdit(
          EditorSnapshot(
            result.draft.body,
            result.draft.body.length,
            result.draft.body.length,
          ),
        );
        changed();
      }
      return;
    }
    sourceMaterials = rows(result.draft.data['source_materials']);
    final nextBody = result.body
        ? mergeSubmissionBody(
            content.text,
            app.submissionHabits['enabled'] == true
                ? applySubmissionHabits(result.draft.body, app.submissionHabits)
                : result.draft.body,
            result.append,
            result.purchaseProof,
          )
        : null;
    if (nextBody != null && nextBody.length > 1000000) {
      message(context, '导入后超出编辑器容量，现有内容未修改');
      return;
    }
    if (result.title) title.text = result.suggestedTitle ?? result.draft.title;
    guideKind = result.kind;
    guideAiImages = result.aiImages;
    if (result.categories != null) {
      categories
        ..clear()
        ..addAll(result.categories!);
    }
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

  Widget mobileTools() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton.tonalIcon(
        onPressed: busy ? null : aiAssistant,
        icon: const Icon(Icons.auto_awesome_rounded),
        label: const Text('AI 投稿助手'),
      ),
      const SizedBox(height: 10),
      LayoutBuilder(
        builder: (c, size) => Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final t in <(String, IconData, VoidCallback?)>[
              (
                '撤销',
                Icons.undo_rounded,
                editHistory?.canUndo == true ? () => undoEdit(false) : null,
              ),
              (
                '重做',
                Icons.redo_rounded,
                editHistory?.canRedo == true ? () => undoEdit(true) : null,
              ),
              ('加粗', Icons.format_bold, () => wrap('<strong>', '</strong>')),
              ('斜体', Icons.format_italic, () => wrap('<em>', '</em>')),
              ('链接', Icons.link_rounded, insertLinkDialog),
              ('上传图片', Icons.image_outlined, upload),
              ('下载卡片', Icons.cloud_download_outlined, insertDownloadDialog),
              ('更多排版', Icons.tune_rounded, moreMobileTools),
            ])
              SizedBox(
                width: (size.maxWidth - 12) / 4,
                child: Tooltip(
                  message: t.$1,
                  child: TextButton(
                    onPressed: busy ? null : t.$3,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 0,
                        vertical: 8,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(t.$2, size: 22),
                        const SizedBox(height: 4),
                        Text(t.$1, style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Future<void> moreMobileTools() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(sheet).height * .7,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                '排版与插入',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: GridView.extent(
                maxCrossAxisExtent: 120,
                childAspectRatio: 1.25,
                padding: const EdgeInsets.all(12),
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                children: [
                  for (final t in <(String, IconData, VoidCallback)>[
                    ('下划线', Icons.format_underlined, () => wrap('<u>', '</u>')),
                    (
                      '删除线',
                      Icons.format_strikethrough,
                      () => wrap('<del>', '</del>'),
                    ),
                    for (final n in [1, 2, 3])
                      (
                        '$n级标题',
                        Icons.title_rounded,
                        () => wrap('<h$n>', '</h$n>'),
                      ),
                    ('段落', Icons.notes_rounded, () => wrap('<p>', '</p>')),
                    ('换行', Icons.keyboard_return_rounded, () => insert('<br>')),
                    (
                      '无序列表',
                      Icons.format_list_bulleted,
                      () => applyEdit(listMarkup(captureEdit(), false)),
                    ),
                    (
                      '有序列表',
                      Icons.format_list_numbered,
                      () => applyEdit(listMarkup(captureEdit(), true)),
                    ),
                    (
                      '引用',
                      Icons.format_quote_rounded,
                      () => wrap('<blockquote>', '</blockquote>'),
                    ),
                    (
                      '网络图片',
                      Icons.add_photo_alternate_outlined,
                      () => insertLinkDialog(image: true),
                    ),
                    (
                      '外部链接',
                      Icons.open_in_browser_outlined,
                      insertExternalDialog,
                    ),
                    ('表格', Icons.table_chart_outlined, () => extra('table')),
                    (
                      '行内代码',
                      Icons.code_rounded,
                      () => wrap('<code>', '</code>'),
                    ),
                    (
                      '代码块',
                      Icons.integration_instructions_outlined,
                      showCodeDialog,
                    ),
                    (
                      '分隔线',
                      Icons.horizontal_rule_rounded,
                      () => insert('\n<hr>\n'),
                    ),
                    ('正文字号', Icons.format_size, chooseFontSize),
                    (
                      '字体',
                      Icons.font_download_outlined,
                      () => extra('fontFamily'),
                    ),
                    (
                      '段落行高',
                      Icons.format_line_spacing,
                      () => extra('lineHeight'),
                    ),
                    ('表情', Icons.emoji_emotions_outlined, () => extra('emoji')),
                    (
                      '特殊字符',
                      Icons.insert_emoticon_outlined,
                      () => extra('special'),
                    ),
                    ('彩虹文字', Icons.palette_outlined, () => extra('rainbow')),
                    ('黑幕文字', Icons.rectangle_outlined, () => extra('blackbar')),
                    (
                      '折叠内容',
                      Icons.unfold_less_rounded,
                      () => extra('collapse'),
                    ),
                    (
                      '随机文件名',
                      Icons.shuffle_rounded,
                      () => extra('randomFileName'),
                    ),
                    ('投票', Icons.poll_outlined, () => extra('poll')),
                    (
                      '抽奖',
                      Icons.card_giftcard_outlined,
                      () => extra('lottery'),
                    ),
                    ('文字颜色', Icons.format_color_text, () => chooseColor(false)),
                    ('背景色', Icons.format_color_fill, () => chooseColor(true)),
                    for (final align in [
                      ('左对齐', 'left', Icons.format_align_left),
                      ('居中', 'center', Icons.format_align_center),
                      ('右对齐', 'right', Icons.format_align_right),
                      ('两端对齐', 'justify', Icons.format_align_justify),
                    ])
                      (
                        align.$1,
                        align.$3,
                        () =>
                            wrap('<p style="text-align:${align.$2}">', '</p>'),
                      ),
                    ('上标', Icons.superscript, () => wrap('<sup>', '</sup>')),
                    ('下标', Icons.subscript, () => wrap('<sub>', '</sub>')),
                    (
                      '增加缩进',
                      Icons.format_indent_increase,
                      () => applyEdit(indentSource(captureEdit(), false)),
                    ),
                    (
                      '减少缩进',
                      Icons.format_indent_decrease,
                      () => applyEdit(indentSource(captureEdit(), true)),
                    ),
                    (
                      '清除格式',
                      Icons.format_clear,
                      () => applyEdit(removeSelectionFormat(captureEdit())),
                    ),
                    ('查找替换', Icons.find_replace_rounded, findReplace),
                    (
                      '全选正文',
                      Icons.select_all_rounded,
                      () {
                        final active = html ? content : visual;
                        active.selection = TextSelection(
                          baseOffset: 0,
                          extentOffset: active.text.length,
                        );
                        contentFocus.requestFocus();
                      },
                    ),
                    (
                      '专注编辑',
                      Icons.fullscreen_rounded,
                      () => setState(() => focusedEditor = !focusedEditor),
                    ),
                    ('导出 HTML', Icons.file_download_outlined, exportPost),
                    ('工具说明', Icons.help_outline_rounded, showEditorHelp),
                    ('编辑字缩小', Icons.text_decrease, () => editorZoom(-1)),
                    ('编辑字放大', Icons.text_increase, () => editorZoom(1)),
                  ])
                    TextButton(
                      onPressed: () {
                        Navigator.pop(sheet);
                        t.$3();
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(t.$2, size: 24),
                          const SizedBox(height: 7),
                          Text(
                            t.$1,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget toolbar() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (MediaQuery.sizeOf(context).width < 700)
        mobileTools()
      else
        Wrap(
          spacing: 2,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Tooltip(
              message: 'AI 投稿助手',
              child: FilledButton.tonalIcon(
                onPressed: busy ? null : aiAssistant,
                icon: const Icon(Icons.auto_awesome_rounded, size: 20),
                label: const Text('AI 投稿助手'),
              ),
            ),
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
            tool('编辑/插入链接', Icons.link_rounded, insertLinkDialog),
            tool('上传正文图片', Icons.image_outlined, upload),
            tool(
              '插入网络图片',
              Icons.add_photo_alternate_outlined,
              () => insertLinkDialog(image: true),
            ),
            tool(
              '插入下载卡片模板',
              Icons.cloud_download_outlined,
              insertDownloadDialog,
            ),
            tool(
              '插入外部链接',
              Icons.open_in_browser_outlined,
              insertExternalDialog,
            ),
            tool('插入表格', Icons.table_chart_outlined, () => extra('table')),
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
            tool('字体', Icons.font_download_outlined, () => extra('fontFamily')),
            tool('段落行高', Icons.format_line_spacing, () => extra('lineHeight')),
            tool('表情', Icons.emoji_emotions_outlined, () => extra('emoji')),
            tool(
              '特殊字符',
              Icons.insert_emoticon_outlined,
              () => extra('special'),
            ),
            tool('彩虹文字', Icons.palette_outlined, () => extra('rainbow')),
            tool('黑幕文字', Icons.rectangle_outlined, () => extra('blackbar')),
            tool('折叠内容', Icons.unfold_less_rounded, () => extra('collapse')),
            tool('随机文件名', Icons.shuffle_rounded, () => extra('randomFileName')),
            tool('插入投票', Icons.poll_outlined, () => extra('poll')),
            tool('插入抽奖', Icons.card_giftcard_outlined, () => extra('lottery')),
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
            tool('全选正文', Icons.select_all_rounded, () {
              final active = html ? content : visual;
              active.selection = TextSelection(
                baseOffset: 0,
                extentOffset: active.text.length,
              );
              contentFocus.requestFocus();
            }),
            tool(
              focusedEditor ? '退出专注编辑' : '专注编辑',
              focusedEditor
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              () => setState(() => focusedEditor = !focusedEditor),
            ),
            tool('打印/导出 HTML', Icons.print_outlined, exportPost),
            tool('工具说明', Icons.help_outline_rounded, showEditorHelp),
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
                    final selection = captureEdit();
                    visual.load(
                      content.text,
                      start: selection.a,
                      end: selection.b,
                    );
                    content.selection = TextSelection(
                      baseOffset: selection.a,
                      extentOffset: selection.b,
                    );
                    setState(() => html = v);
                    changed();
                  },
          ),
          FilterChip(
            label: const Text('实时预览'),
            selected: preview,
            onSelected: (v) => setState(() => preview = v),
          ),
          Text(
            html
                ? '代码视图 · 直接编辑 HTML'
                : (isAndroid ? '正常模式 · 直接打字，长按图片编辑' : '正常模式 · 直接打字和插图，右键图片可编辑'),
            style: const TextStyle(fontSize: 11, color: violet),
          ),
          Text(
            '${html ? '源码' : '正文'} ${(html ? content.text : visual.text).runes.length} 字符 · 编辑字号 ${sourceFontSize.toInt()}',
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
    final insertion = captureEdit();
    String? uploaded;
    setState(() => busy = true);
    try {
      await action(context, () async {
        final bytes = await (widget.imagePicker ?? pickJpeg)(context);
        if (bytes == null || !mounted || app!.uid != owner) return;
        final result = await app!.site.upload('upload/image', 'image', bytes);
        if (!mounted || app!.uid != owner) return;
        final url = uploadedUrl(result);
        if (!url.startsWith('https:') || !safeExternal(url)) {
          throw ApiFailure(400, '上传结果未包含有效图片地址');
        }
        uploaded = url;
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (!mounted || app!.uid != owner || uploaded == null) return;
    if (cover) {
      thumb.text = uploaded!;
    } else if (content.text == insertion.text) {
      applyEdit(
        insertMarkup(
          insertion,
          '<img src="${const HtmlEscape().convert(uploaded!)}" alt="图片">',
        ),
      );
    } else {
      // Never overwrite intervening edits if a platform picker changed focus.
      insert('<img src="${const HtmlEscape().convert(uploaded!)}" alt="图片">');
    }
  }

  Future<void> insertDownloadDialog() async {
    final selection = captureEdit();
    final result = await showDownloadTemplateDialog(context);
    if (result != null && mounted && app!.uid == owner) {
      applyEdit(
        insertMarkup(
          content.text == selection.text ? selection : captureEdit(),
          result,
        ),
      );
    }
  }

  Future<void> showEditorHelp() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('投稿编辑工具'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Text(
            '正常模式：直接输入文字，选中文字后加粗、改字号或调整颜色。上传正文图片会插入到原先光标处，右键图片可以更换、改说明、尺寸、链接或删除。\n\n'
            'HTML 源码：点击按钮切换代码视图。切换会保留原有图片、排版与网站组件；不支持直接显示的复杂组件会以卡片保留。\n\n'
            '资源：下载链接包含标题、上传时间、来源、提取码、解压码和多个地址；外部链接由官网解析为嵌入组件。表格卡片可点击编辑。\n\n'
            '扩展：表情、特殊字符、折叠内容、彩虹文字、黑幕文字、随机文件名、投票与抽奖。投票管理需要官网权限；创建前会再次确认。\n\n'
            '撤销与重做支持工具栏和 $primaryModifierLabel+Z / $primaryModifierLabel+Shift+Z。$primaryModifierLabel+B 加粗，$primaryModifierLabel+I 斜体，$primaryModifierLabel+U 下划线，$primaryModifierLabel+F 查找替换。\n\n'
            '实时预览可独立用鼠标滚轮查看长文章。专注编辑收起标题和投稿资料。打印会导出安全的 HTML 文件，并可在系统浏览器中按 $primaryModifierLabel+P 打印。\n\n'
            '本机草稿自动保存。只有点击提交并确认后才会提交网站。',
            style: TextStyle(height: 1.8),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('知道了')),
      ],
    ),
  );

  Future<void> exportPost() async {
    if (isAndroid) {
      await action(context, () async {
        final saved = await platformChannel.invokeMethod<bool>('saveHtml', {
          'name': '星屿投稿.html',
          'content': printablePost(title.text, content.text),
        });
        if (mounted && saved == true) message(context, '文章已导出');
      });
      return;
    }
    final open = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('打印与导出'),
        content: Text(
          '将当前标题和正文保存为 HTML 文件。选择“保存并打开”会用系统浏览器打开文件，再按 $primaryModifierLabel+P 打印或另存为 PDF。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('只保存 HTML'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('保存并打开'),
          ),
        ],
      ),
    );
    if (open == null || !mounted) return;
    await action(context, () async {
      final location = await getSaveLocation(
        suggestedName: '星屿投稿.html',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'HTML文章', extensions: ['html', 'htm']),
        ],
      );
      if (location == null || !mounted) return;
      final bytes = Uint8List.fromList(
        utf8.encode(printablePost(title.text, content.text)),
      );
      await XFile.fromData(bytes, mimeType: 'text/html').saveTo(location.path);
      if (open &&
          !await launchUrl(
            Uri.file(location.path),
            mode: LaunchMode.externalApplication,
          )) {
        throw ApiFailure(400, '文件已保存，但系统浏览器未能打开；请从保存位置手动打开');
      }
      if (mounted) message(context, '文章已导出');
    });
  }

  Future<void> extra(String tool) async {
    final selection = captureEdit();
    final result = await showEditorExtra(
      context,
      tool,
      selectedHtml: selection.text.substring(selection.a, selection.b),
      api: app!.site,
      account: app!.user,
      uploadImage: uploadForDialog,
    );
    if (!mounted || app!.uid != owner || result == null) return;
    applyEdit(
      insertMarkup(
        content.text == selection.text ? selection : captureEdit(),
        result,
      ),
    );
  }

  Future<String?> uploadForDialog() async {
    if (busy) return null;
    String? uploaded;
    setState(() => busy = true);
    try {
      await action(context, () async {
        final bytes = await (widget.imagePicker ?? pickJpeg)(context);
        if (bytes == null || !mounted || app!.uid != owner) return;
        final value = await app!.site.upload('upload/image', 'image', bytes);
        if (!mounted || app!.uid != owner) return;
        final url = uploadedUrl(value);
        if (!url.startsWith('https:') || !safeExternal(url)) {
          throw ApiFailure(400, '上传结果未包含有效图片地址');
        }
        uploaded = url;
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
    return mounted && app!.uid == owner ? uploaded : null;
  }

  Future<void> editImageAtom(int start, int end, String markup) async {
    if (busy) return;
    final original = content.text;
    final result = await editEditorImage(
      context,
      markup,
      uploadImage: uploadForDialog,
    );
    if (!mounted || app!.uid != owner || result == null) return;
    if (content.text != original) {
      message(context, '正文已发生变化，请重新右键选择图片');
      return;
    }
    applyEdit(
      EditorSnapshot(
        original.replaceRange(start, end, result),
        start + result.length,
        start + result.length,
      ),
    );
  }

  Future<void> editComponent(int start, int end, String markup) async {
    if (busy) return;
    final original = content.text;
    String? result;
    if (markup.toLowerCase().startsWith('<table')) {
      result = await showEditorExtra(
        context,
        'table',
        selectedHtml: markup,
        api: app!.site,
        account: app!.user,
      );
    } else if (markup.startsWith('[dlbox')) {
      result = await showDownloadTemplateDialog(context, initialMarkup: markup);
    } else if (markup.startsWith('[iframe]') && markup.endsWith('[/iframe]')) {
      result = await showExternalTemplateDialog(
        context,
        initialUrl: markup.substring(8, markup.length - 9),
      );
    } else {
      message(context, '该网站组件已原样保留；可选中后重新插入，或切换 HTML 源码精确编辑');
      return;
    }
    if (!mounted || app!.uid != owner || result == null) return;
    if (content.text != original) return;
    applyEdit(
      EditorSnapshot(
        original.replaceRange(start, end, result),
        start + result.length,
        start + result.length,
      ),
    );
  }

  Future<void> insertExternalDialog() async {
    final selection = captureEdit();
    final result = await showExternalTemplateDialog(context);
    if (result != null && mounted && app!.uid == owner) {
      applyEdit(
        insertMarkup(
          content.text == selection.text ? selection : captureEdit(),
          result,
        ),
      );
    }
  }

  Future<void> selectCategories() async {
    if (app!.categories.isEmpty) await app!.loadCategories();
    if (!mounted || app!.uid != owner) return;
    final selected = await showSubmissionCategories(context, app!, categories);
    if (selected != null && mounted && app!.uid == owner) {
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
    String guideNote = '';
    try {
      final guide = await SubmissionGuidance.load();
      final issues = guide.check(
        title: title.text,
        body: bodyHtml(),
        selected: categories,
        tree: app!.categories,
        kind: guideKind,
        aiImages: guideAiImages,
      );
      issues.addAll(
        extraPreflight(
          title.text,
          bodyHtml(),
          cover: thumb.text,
          sourceUrls: sourceMaterials.map((s) => text(s['url'])),
        ).map((m) => GuideIssue('content.check', m)),
      );
      if (issues.isNotEmpty) {
        guideNote =
            '\n\n规范待核对 ${issues.length} 项：\n${issues.take(4).map((i) => '• ${i.message}').join('\n')}';
      }
    } catch (_) {
      guideNote = '\n规则检查暂不可用，请手动核对官网须知。';
    }
    if (!mounted) return;
    if (!await confirm(
          context,
          widget.route.id == 0 ? '提交这篇投稿？' : '保存网站上的投稿？',
          '${title.text.trim()}\n状态：${postStatuses[status]}${status == 'future' ? '\n上海时间：${schedule.text}' : ''}\n内容将同步到 cangku.moe。$guideNote',
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
        padding: EdgeInsets.all(
          focusedEditor
              ? 12
              : MediaQuery.sizeOf(context).width < 700
              ? 16
              : 32,
        ),
        width: focusedEditor ? 1800 : 1500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Heading(
              widget.route.id == 0 ? '写下新的故事' : '继续你的创作',
              isAndroid
                  ? '本机草稿自动保存 · 支持正常模式与源码编辑'
                  : '本机草稿自动保存 · $primaryModifierLabel+S 保存本机 · $primaryModifierLabel+Enter 提交确认',
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
            if (!focusedEditor) ...[
              TextField(
                controller: title,
                enabled: !busy,
                maxLength: 500,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
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
            ],
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
                              primaryShortcut(LogicalKeyboardKey.keyB): () =>
                                  wrap('<strong>', '</strong>'),
                              primaryShortcut(LogicalKeyboardKey.keyI): () =>
                                  wrap('<em>', '</em>'),
                              primaryShortcut(LogicalKeyboardKey.keyU): () =>
                                  wrap('<u>', '</u>'),
                              primaryShortcut(LogicalKeyboardKey.keyZ): () =>
                                  undoEdit(false),
                              primaryShortcut(
                                LogicalKeyboardKey.keyZ,
                                shift: true,
                              ): () =>
                                  undoEdit(true),
                              primaryShortcut(LogicalKeyboardKey.keyF):
                                  findReplace,
                            },
                            child: EditorImeAnchor(
                              focusNode: contentFocus,
                              controller: html ? content : visual,
                              child: TextField(
                                key: const Key('editor.content'),
                                controller: html ? content : visual,
                                focusNode: contentFocus,
                                enabled: !busy,
                                minLines: isAndroid ? 10 : 21,
                                maxLines: isAndroid ? 18 : 45,
                                // Default EditableText forces every line to the
                                // base font height, which overlaps tall widgets.
                                strutStyle: html
                                    ? null
                                    : const StrutStyle(forceStrutHeight: false),
                                style: TextStyle(
                                  fontSize: sourceFontSize,
                                  height: 1.8,
                                  fontFamily: html ? monoFont : null,
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
                                SizedBox(
                                  height:
                                      (MediaQuery.sizeOf(context).height * .62)
                                          .clamp(320, 760),
                                  child: Scrollbar(
                                    controller: previewScroll,
                                    thumbVisibility: true,
                                    child: SingleChildScrollView(
                                      key: const Key('editor.preview.scroll'),
                                      controller: previewScroll,
                                      padding: const EdgeInsets.only(right: 14),
                                      child: RichContent(
                                        ReaderDocument.parse(
                                          bodyHtml(),
                                          inlineResources: true,
                                        ).content,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
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
              '草稿只保存在本机。上传图片和提交投稿都会写入网站，提交前请确认内容与权限。',
              style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.8),
            ),
            const SizedBox(height: 25),
          ],
        ),
      ),
    );
  }
}
