import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../core/ai.dart';
import '../core/api.dart';
import '../core/dynamic_template_store.dart';
import '../core/dynamic_templates.dart';
import '../core/media.dart';
import '../core/reader.dart';
import '../core/state.dart';
import '../core/submission_guidance.dart';
import '../core/submission_workbench.dart';
import '../ui/shared.dart';
import '../ui/submission_categories.dart';
import 'authoring.dart' show postFingerprint;
import 'account.dart' show uploadedUrl;

typedef OpenDynamicDraft = Future<void> Function(
  String taskId,
  Json snapshot,
  int postId,
);

/// Deliberately independent from the existing assistant and its editor state.
class DynamicTemplatesPage extends StatefulWidget {
  final AppState app;
  final OpenDynamicDraft onOpenDraft;
  const DynamicTemplatesPage(this.app, {super.key, required this.onOpenDraft});
  @override
  State<DynamicTemplatesPage> createState() => _DynamicTemplatesPageState();
}

class _DynamicTemplatesPageState extends State<DynamicTemplatesPage> {
  DynamicTemplateStore? store;
  SubmissionGuidance? guide;
  final transport = AiTransport();
  final messageInput = TextEditingController();
  final searchInput = TextEditingController();
  final chatScroll = ScrollController();
  Json? task;
  List<Json> messages = [];
  List<Json> memories = [];
  int tab = 0;
  late final owner = widget.app.uid;
  bool busy = false;
  String error = '';
  bool get current => mounted && widget.app.uid == owner;
  bool get preservesFullBody =>
      object(task?['fields'])['full_body'] == true &&
      text(object(task?['fields'])['body_html']).isNotEmpty;
  bool lockedBodyField(String key) =>
      preservesFullBody &&
      const {'description', 'proof', 'code', 'password'}.contains(key);
  @override
  void initState() {
    super.initState();
    unawaited(initialize());
  }

  Future<void> initialize() async {
    try {
      final value = await DynamicTemplateStore.open(
        owner,
        directory: widget.app.directory,
      );
      if (!current) {
        value.close();
        return;
      }
      store = value;
      guide = await SubmissionGuidance.load();
      if (widget.app.categories.isEmpty) await widget.app.loadCategories();
      if (current) setState(() {});
    } catch (e) {
      if (current) setState(() => error = '$e');
    }
  }

  @override
  void dispose() {
    transport.close();
    store?.close();
    messageInput.dispose();
    searchInput.dispose();
    chatScroll.dispose();
    super.dispose();
  }

  Future<void> perform(Future<void> Function() action) async {
    if (busy || !current) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await action();
    } catch (e) {
      if (current) {
        setState(() => error = '$e');
        if (task != null) {
          store!.addMessage(
            text(task!['id']),
            'assistant',
            '本步未完成：$e。已保留现有资料，可重试。',
          );
          reloadMessages();
        }
      }
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  void save() {
    if (task != null) store!.saveTask(task!);
    if (current) setState(() {});
  }

  void reply(String value) {
    if (task == null) return;
    store!.addMessage(text(task!['id']), 'assistant', value);
    reloadMessages();
  }

  void reloadMessages() {
    if (task != null) messages = store!.messages(text(task!['id']));
    if (current) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (current && chatScroll.hasClients) {
        chatScroll.animateTo(
          chatScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void selectTask(Json value) {
    task = copyDynamicJson(value);
    error = '';
    reloadMessages();
  }

  void createTask(DynamicTemplate value) {
    task = newDynamicTask(value);
    store!.saveTask(task!);
    store!.addMessage(
      text(task!['id']),
      'assistant',
      '已使用「${value.name}」v${value.version}。发送作品链接、下载链接和补充要求；也可以到“资料”上传封面与证明。缺少的资料会列在这里，预览确认后再交给编辑器提交。',
    );
    tab = 0;
    reloadMessages();
  }

  Future<Json> fetchSource(String url) async {
    final uri = aiSourceUrl(url),
        match = RegExp(r'^/archives/(\d+)').firstMatch(uri.path);
    if ((uri.host == 'cangku.moe' || uri.host == 'www.cangku.moe') &&
        match != null) {
      final post = object(
        (await widget.app.get('post/info', {
          'id': int.parse(match[1]!),
          'exclude_view': 1,
        }))['data'],
      );
      if (post.isEmpty) throw ApiFailure(404, '没有找到这篇投稿');
      return dynamicPageSource(post, url);
    }
    return transport.source(url);
  }

  Future<void> extractSources() async {
    final value = task;
    if (value == null) return;
    final fields = object(value['fields']),
        urls = (fields['source_urls'] as List? ?? [])
            .whereType<String>()
            .toList();
    final existing = rows(value['sources']).map((s) => text(s['url'])).toSet();
    for (final url in urls.where((u) => !existing.contains(u))) {
      final source = await fetchSource(url);
      if (!current || task != value) return;
      absorbDynamicSource(value, source, guide!, widget.app.categories);
      final inferred = guide!.guess([source]);
      if (inferred != 'other' &&
          inferred != DynamicTemplate(object(value['template'])).kind) {
        reply(
          '来源识别为${text(guide!.profile(inferred)['label'])}，与所选模板的作品类型不同，请核对模板和分类。',
        );
      }
      store!.addMessage(
        text(value['id']),
        'tool',
        '已提取来源：${text(source['title'])}\n$url',
      );
      save();
    }
  }

  Future<void> send() async {
    final input = messageInput.text.trim();
    if (input.isEmpty || store == null) return;
    if (RegExp(r'继续上次|继续之前|恢复任务|找回|查找记录|搜索记忆|上次.*投稿').hasMatch(input)) {
      await recoverTaskIntent(input);
      return;
    }
    if (task?['needs_latest'] == true && number(task?['post_id']) > 0) {
      setState(() {
        error = '这篇投稿已提交到官网，请先在“资料”载入官网最新内容，再继续修改。';
        tab = 1;
      });
      return;
    }
    if (task == null) {
      final candidates = matchDynamicTemplates(store!.templates, input);
      if (candidates.isNotEmpty) {
        final selected = await showDynamicTemplateDialog<DynamicTemplate>(
          context: context,
          builder: (c) => SimpleDialog(
            title: const Text('使用哪个模板？'),
            children: [
              for (final t in candidates)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, t),
                  child: ListTile(
                    leading: const Icon(Icons.auto_awesome_mosaic_rounded),
                    title: Text(t.name),
                    subtitle: Text('${aiTypes[t.kind]} · v${t.version}'),
                  ),
                ),
            ],
          ),
        );
        if (!current || selected == null) return;
        createTask(selected);
      } else {
        message(context, '先选择一个模板，或创建自己的模板');
        return;
      }
    }
    messageInput.clear();
    await perform(() async {
      store!.addMessage(text(task!['id']), 'user', input);
      final changes = absorbDynamicMessage(task!, input);
      task!['last_instruction'] = input;
      save();
      reloadMessages();
      await extractSources();
      if (!current) return;
      final fields = object(task!['fields']);
      if (changes.isEmpty &&
          RegExp(r'修改|改成|缩短|精简|整理|排版|润色|翻译|审核|删除|删掉|添加|增加|替换')
              .hasMatch(input) &&
          (text(fields['description']).isNotEmpty ||
              text(fields['body_html']).isNotEmpty ||
              rows(task!['sources']).isNotEmpty)) {
        await applyAiInstruction(input);
        if (!current) return;
      }
      final missing = dynamicMissing(task!);
      reply(
        '${changes.isEmpty ? '已保存这条要求。需要改写正文时，点击“AI 按要求修改”。' : changes.join('；')}\n${missing.isEmpty ? '资料已齐全，可以查看预览并继续投稿。' : '还需补充：${missing.map((k) => dynamicFieldNames[k]).join('、')}。'}',
      );
      save();
    });
  }

  Future<void> recoverTaskIntent(String input) async {
    if (store == null) return;
    final terms = <String>{
      ...RegExp(
        r'RJ[0-9]{6,12}',
        caseSensitive: false,
      ).allMatches(input).map((m) => m[0]!.toUpperCase()),
      for (final name in ['游戏', '音声', '漫画', '动画'])
        if (input.contains(name)) name,
    };
    final reference = RegExp(r'[「“"]([^」”"]{2,80})[」”"]').firstMatch(input)?[1];
    if (reference != null) terms.add(reference);
    final found = <String, Json>{};
    for (final term in terms) {
      for (final memory in store!.search(term)) {
        final id = text(memory['task_id']);
        if (id.isNotEmpty) {
          final value = store!.task(id);
          if (value != null) found[id] = value;
        }
      }
    }
    for (final candidate in store!.tasks) {
      final searchable =
          '${text(object(candidate['fields'])['title'])} ${text(object(candidate['template'])['name'])} ${jsonEncode(object(candidate['fields'])['source_urls'] ?? [])}';
      if (terms.isEmpty || terms.any(searchable.contains)) {
        found.putIfAbsent(text(candidate['id']), () => candidate);
      }
    }
    if (!mounted) return;
    if (found.isEmpty) {
      setState(() => error = '没有找到对应历史任务，可以到“记忆”换一个作品名或 RJ 编号搜索。');
      return;
    }
    final selected = await showDynamicTemplateDialog<Json>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('继续哪项投稿？'),
        children: [
          for (final candidate in found.values.take(12))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, candidate),
              child: ListTile(
                leading: const Icon(Icons.history_rounded),
                title: Text(
                  text(object(candidate['fields'])['title'], '未命名投稿'),
                ),
                subtitle: Text(
                  '${text(object(candidate['template'])['name'])} · ${dynamicStatusLabel(text(candidate['status']))}',
                ),
              ),
            ),
        ],
      ),
    );
    if (selected == null || !current) return;
    messageInput.clear();
    selectTask(selected);
    tab = 0;
    store!.addMessage(text(task!['id']), 'user', input);
    reply(
      '已恢复这项投稿的资料、模板版本和对话。${task!['needs_latest'] == true ? '这篇已提交的作品需要先载入官网最新内容，再继续修改。' : '可以继续补充资料或发送修改要求。'}',
    );
  }

  Future<Json> config() async {
    final raw = await widget.app.site.storage.read(key: 'ai.$owner');
    if (raw == null) return <String, dynamic>{};
    return object(jsonDecode(raw));
  }

  Future<void> settings() async {
    final value = await config();
    if (!mounted || widget.app.uid != owner) return;
    var custom = value['custom'] == true;
    final address = TextEditingController(text: text(value['address'])),
        key = TextEditingController(text: text(value['key'])),
        model = TextEditingController(text: text(value['model']));
    final yes = await showDynamicTemplateDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('动态模板 · AI 设置'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('使用自定义模型'),
                    subtitle: const Text('与现有 AI 投稿助手共用模型配置'),
                    value: custom,
                    onChanged: (v) => set(() => custom = v),
                  ),
                  if (custom) ...[
                    TextField(
                      controller: address,
                      decoration: const InputDecoration(
                        labelText: 'HTTPS API 地址',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: model,
                      decoration: const InputDecoration(labelText: '模型名称'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: key,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'API Key'),
                    ),
                  ] else
                    const Text(
                      '使用内置 AI 的每日共享额度。网页提取、缺项检查和原文排版在本机完成，不消耗 AI 次数。',
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (custom) {
                  try {
                    aiEndpoint(address.text);
                    if (model.text.trim().isEmpty || key.text.trim().isEmpty) {
                      throw const FormatException('请填写模型和 API Key');
                    }
                  } catch (e) {
                    message(c, '$e');
                    return;
                  }
                }
                Navigator.pop(c, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (yes == true && current) {
      await widget.app.site.storage.write(
        key: 'ai.$owner',
        value: jsonEncode({
          'custom': custom,
          'address': address.text.trim(),
          'model': model.text.trim(),
          'key': key.text.trim(),
        }),
      );
    }
    address.dispose();
    key.dispose();
    model.dispose();
  }

  Future<Json> runWorkbench(Json request) async {
    final cfg = await config();
    if (!mounted || widget.app.uid != owner) throw ApiFailure(409, '账号已切换');
    if (utf8.encode(jsonEncode(request)).length >
        (cfg['custom'] == true ? 200000 : 12000)) {
      throw ApiFailure(413, '资料过长，请先在“资料”填写较短的作品介绍，或使用自定义模型。原文已保留');
    }
    Json result;
    if (cfg['custom'] == true) {
      if (text(cfg['key']).isEmpty || text(cfg['model']).isEmpty) {
        throw ApiFailure(400, '请先配置自定义 AI');
      }
      final response = await transport.json(
        aiEndpoint(text(cfg['address'])),
        token: text(cfg['key']),
        body: {
          'model': text(cfg['model']),
          'stream': false,
          'max_tokens': 6000,
          'messages': [
            {'role': 'system', 'content': workbenchSystem},
            {'role': 'user', 'content': jsonEncode(request)},
          ],
        },
      );
      final choices = rows(response['choices']);
      if (choices.isEmpty) throw ApiFailure(502, 'AI 没有返回结果');
      result = parseWorkbench(
        object(choices.first['message'])['content'],
        request,
      );
    } else {
      if (!widget.app.verified) {
        final yes = await confirm(
          context,
          '认证并使用内置 AI？',
          '会将当前会话交给星屿服务向官网核验；所选作品文字交给 Cloudflare AI。每次调用与现有投稿助手共用每日额度。不上传下载密码和自购证明。',
          action: '认证并继续',
        );
        if (!yes || !current) throw ApiFailure(499, '已取消');
        await widget.app.enableIdentity();
      }
      if (!current) throw ApiFailure(409, '账号已切换');
      final response = await transport.json(
        Uri.parse('$serviceOrigin/ai/v3/task'),
        token: widget.app.token,
        body: request,
        builtin: true,
        timeout: const Duration(seconds: 180),
      );
      result = parseWorkbench(response['result'], request);
    }
    return result;
  }

  Future<void> aiEdit() async =>
      perform(() => applyAiInstruction(text(task?['last_instruction'])));

  Future<DynamicTemplate> runTemplateRefine(DynamicTemplate template) async {
    final request = dynamicTemplateRefineRequest(template);
    final cfg = await config();
    if (!mounted || widget.app.uid != owner) throw ApiFailure(409, '账号已切换');
    if (utf8.encode(jsonEncode(request)).length > 12000) {
      throw ApiFailure(413, '模板与网页摘录超过12KB，请缩短模板说明后重试');
    }
    dynamic raw;
    if (cfg['custom'] == true) {
      if (text(cfg['key']).isEmpty || text(cfg['model']).isEmpty) {
        throw ApiFailure(400, '请先配置自定义 AI');
      }
      final response = await transport.json(
        aiEndpoint(text(cfg['address'])),
        token: text(cfg['key']),
        body: {
          'model': text(cfg['model']),
          'stream': false,
          'max_tokens': 2500,
          'temperature': 0,
          'messages': [
            {'role': 'system', 'content': dynamicTemplateSystem},
            {'role': 'user', 'content': jsonEncode(request)},
          ],
        },
      );
      final choices = rows(response['choices']);
      if (choices.isEmpty) throw ApiFailure(502, 'AI 没有返回模板结果');
      raw = object(choices.first['message'])['content'];
    } else {
      if (!widget.app.verified) {
        final yes = await confirm(
          context,
          '认证并使用内置 AI？',
          '会将当前会话交给星屿服务向官网核验；模板规则与网页前1800字交给 Cloudflare AI。此操作与现有投稿助手共用每日额度。生成结果需要你确认保存。',
          action: '认证并继续',
        );
        if (!yes || !current) throw ApiFailure(499, '已取消');
        await widget.app.enableIdentity();
      }
      if (!current) throw ApiFailure(409, '账号已切换');
      final response = await transport.json(
        Uri.parse('$serviceOrigin/ai/v3/task'),
        token: widget.app.token,
        body: request,
        builtin: true,
        timeout: const Duration(seconds: 180),
      );
      raw = response['result'];
    }
    if (!current) throw ApiFailure(409, '账号已切换');
    return parseDynamicTemplateProposal(raw, template);
  }

  Future<void> applyAiInstruction(String instruction) async {
    if (task == null) throw ApiFailure(400, '请先创建投稿任务');
    if (task!['needs_latest'] == true && number(task!['post_id']) > 0) {
      throw ApiFailure(409, '请先在“资料”载入官网最新内容，再修改已提交的作品');
    }
    if (instruction.trim().isEmpty) throw ApiFailure(400, '请先发送修改要求');
    final fields = object(task!['fields']);
    final body = dynamicDescription(task!);
    final document = WorkDocument(body);
    if (document.segments.isEmpty) throw ApiFailure(400, '请先提取作品来源或填写作品介绍');
    final request = <String, dynamic>{
      'request_id': nonce(),
      'task': 'command',
      'title': text(fields['title']),
      'instruction': dynamicAiInstruction(task!, instruction),
      'segments': document.segments,
      'sources': <Json>[],
    };
    final result = await runWorkbench(request);
    if (!current) return;
    final edits = rows(result['edits']);
    if (edits.isNotEmpty) {
      fields['body_html'] = document.apply(edits);
      task!['fields'] = fields;
      task!['status'] = 'collecting';
      save();
    }
    reply(
      [
        edits.isEmpty ? 'AI 未修改正文。' : '已按要求修改作品介绍；原始来源和下载模块保留。',
        ...(result['notes'] as List).map(text),
      ].join('\n'),
    );
  }

  Future<void> refineTemplate(DynamicTemplate template) async =>
      perform(() async {
        final proposed = await runTemplateRefine(template);
        if (!current) return;
        await editTemplate(template: proposed);
      });

  Future<void> editTemplate({DynamicTemplate? template, Json? learned}) async {
    if (store == null) return;
    final initial =
        template?.data ?? learned ?? starterDynamicTemplates().last.data;
    final data = copyDynamicJson(initial);
    if (template == null) data['id'] = nonce();
    final name = TextEditingController(
      text: template == null && learned == null ? '我的模板' : text(data['name']),
    );
    final titleFormat = TextEditingController(
      text: text(data['title_format'], '{title}{rj}'),
    );
    final notes = TextEditingController(text: text(data['notes']));
    final aliases = TextEditingController(text: text(data['aliases']));
    var kind = text(data['kind'], 'other'),
        proof = data['proof_when_purchased'] != false;
    final required = (data['required'] as List? ?? [])
        .whereType<String>()
        .toSet();
    final order = (data['sections'] as List? ?? dynamicSections.keys.toList())
        .cast<String>()
        .toList();
    final result = await showDynamicTemplateDialog<DynamicTemplate>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(template == null ? '创建动态模板' : '编辑模板 · 保存为新版本'),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: '模板名称'),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration: const InputDecoration(labelText: '作品类型'),
                    items: [
                      for (final e in aiTypes.entries.where(
                        (e) => e.key != 'auto',
                      ))
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => set(() => kind = v!),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: titleFormat,
                    decoration: const InputDecoration(
                      labelText: '标题格式',
                      helperText: '{title} 为原标题，{rj} 为来源中的 RJ 编号',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '必填资料',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final f in dynamicFieldNames.entries)
                        FilterChip(
                          label: Text(f.value),
                          selected: required.contains(f.key),
                          onSelected: (v) => set(
                            () => v
                                ? required.add(f.key)
                                : required.remove(f.key),
                          ),
                        ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('自购时必须提供证明'),
                    value: proof,
                    onChanged: (v) => set(() => proof = v),
                  ),
                  const Text(
                    '正文顺序',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (var i = 0; i < order.length; i++)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.drag_indicator_rounded,
                        color: Theme.of(c).colorScheme.primary,
                      ),
                      title: Text(dynamicSections[order[i]] ?? order[i]),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '上移',
                            onPressed: i == 0
                                ? null
                                : () => set(() {
                                    final v = order.removeAt(i);
                                    order.insert(i - 1, v);
                                  }),
                            icon: const Icon(Icons.keyboard_arrow_up_rounded),
                          ),
                          IconButton(
                            tooltip: '下移',
                            onPressed: i == order.length - 1
                                ? null
                                : () => set(() {
                                    final v = order.removeAt(i);
                                    order.insert(i + 1, v);
                                  }),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: aliases,
                    decoration: const InputDecoration(
                      labelText: '别名与关键词',
                      helperText: '不选模板时可根据这些词找到模板',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: '规则说明与个人偏好'),
                  ),
                  if (text(data['source_url']).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        '参考来源：${text(data['source_url'])}',
                        style: Theme.of(c).textTheme.bodySmall,
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
                try {
                  Navigator.pop(
                    c,
                    DynamicTemplate({
                      ...data,
                      'name': name.text,
                      'kind': kind,
                      'title_format': titleFormat.text,
                      'required': required.toList(),
                      'proof_when_purchased': proof,
                      'sections': order,
                      'notes': notes.text,
                      'aliases': aliases.text,
                    }),
                  );
                } catch (e) {
                  message(c, '$e');
                }
              },
              child: const Text('保存模板'),
            ),
          ],
        ),
      ),
    );
    if (result != null && current) {
      store!.saveTemplate(result);
      setState(() {});
    }
    name.dispose();
    titleFormat.dispose();
    notes.dispose();
    aliases.dispose();
  }

  Future<void> learn() async {
    final url = TextEditingController(), material = TextEditingController();
    final input = await showDynamicTemplateDialog<Json>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('从网页学习模板'),
        content: SizedBox(
          width: 550,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: url,
                  decoration: const InputDecoration(
                    labelText: '投稿范例或投稿须知链接',
                    prefixIcon: Icon(Icons.link_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: material,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '也可粘贴范例或规则',
                    helperText: '网页无法提取时，粘贴内容即可继续。',
                  ),
                ),
                const SizedBox(height: 12),
                const Text('先提取结构与规则，再由你确认必填项和排版。网页内容不会执行代码或改变应用权限。'),
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
              if (url.text.trim().isEmpty && material.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(c, {
                'url': url.text.trim(),
                'text': material.text.trim(),
              });
            },
            child: const Text('提取模板'),
          ),
        ],
      ),
    );
    url.dispose();
    material.dispose();
    if (input == null || !current) return;
    await perform(() async {
      final source = text(input['text']).isNotEmpty
          ? <String, dynamic>{
              'url': text(input['url']),
              'title': '粘贴资料',
              'text': text(input['text']),
              'blocks': [
                for (final p in text(input['text']).split('\n'))
                  {'kind': 'p', 'text': p},
              ],
            }
          : await fetchSource(text(input['url']));
      if (!current) return;
      final learned = learnDynamicTemplate(source);
      await editTemplate(learned: learned.data);
    });
  }

  Future<void> updateField(String key, String value) async {
    if (task == null) return;
    if (lockedBodyField(key)) {
      throw ApiFailure(409, '已保留官网完整正文，请通过对话修改介绍，或到原编辑器修改正文组件');
    }
    final fields = object(task!['fields']);
    fields[key] = value;
    if (key == 'description') fields.remove('body_html');
    task!['fields'] = fields;
    task!['status'] = 'collecting';
    save();
  }

  Future<void> upload(String key) async => perform(() async {
    if (task == null) return;
    if (lockedBodyField(key)) {
      throw ApiFailure(409, '自购证明已包含在完整正文中，请到原编辑器修改');
    }
    final bytes = await pickJpeg(context);
    if (bytes == null || !current) return;
    final result = await widget.app.site.upload('upload/image', 'image', bytes);
    if (!current) return;
    final url = uploadedUrl(result);
    if (!safeExternal(url) || !url.startsWith('https://')) {
      throw ApiFailure(502, '官网图床没有返回有效图片地址');
    }
    await updateField(key, url);
    reply('已上传${dynamicFieldNames[key]}到官网图床。');
  });
  Future<void> chooseCategories() async => perform(() async {
    final chosen = await showSubmissionCategories(
      context,
      widget.app,
      (task!['category_ids'] as List? ?? []).map(number).toSet(),
    );
    if (chosen != null && current) {
      task!['category_ids'] = chosen.toList();
      save();
    }
  });
  Future<void> previewDraft() async {
    if (task == null) return;
    final missing = dynamicMissing(task!);
    if (missing.isNotEmpty) {
      setState(
        () => error =
            '还需补充：${missing.map((k) => dynamicFieldNames[k]).join('、')}',
      );
      tab = 1;
      return;
    }
    await perform(() async {
      final value = task!, snapshot = dynamicEditorSnapshot(task!, owner);
      final notes = guide!
          .check(
            title: text(snapshot['title']),
            body: text(snapshot['content']),
            selected: (snapshot['category_ids'] as List).map(number).toSet(),
            tree: widget.app.categories,
            kind: DynamicTemplate(object(value['template'])).kind,
          )
          .map((n) => n.message)
          .toList();
      final queries = duplicateQueries(
        text(snapshot['title']),
        (object(value['fields'])['source_urls'] as List? ?? []).map(text),
      ).take(2).toList();
      final queryKey = queries.join('\n');
      if (value['duplicate_query_key'] != queryKey) {
        final duplicates = <int, Json>{};
        try {
          for (final query in queries) {
            final result = await widget.app.get('post/search', {
              'search': query,
              'page': 1,
              'per_page': 8,
              'simple': 1,
              'include': 'user,categories:simple',
            });
            if (!current || task != value) return;
            for (final post in rows(result['data'])) {
              final id = number(post['id']);
              if (id > 0 && id != number(value['post_id'])) {
                duplicates[id] = post;
              }
            }
          }
          value['duplicate_results'] = duplicates.values.toList();
          value['duplicate_query_key'] = queryKey;
          value['duplicate_note'] = duplicates.isEmpty
              ? '当前搜索结果未找到疑似重复，仍需人工核对。'
              : '找到 ${duplicates.length} 项疑似重复，请核对作品版本。';
        } catch (_) {
          value['duplicate_note'] = '官网重复检索暂不可用，可重试检查或在提交前手动搜索。';
        }
      }
      if (!current || task != value) return;
      value['preflight_notes'] = notes;
      value['status'] = 'ready';
      save();
      setState(() => tab = 2);
    });
  }

  Future<void> openEditor() async => perform(() async {
    if (task == null) return;
    if (text(task!['submitted_at']).isNotEmpty &&
        number(task!['post_id']) <= 0) {
      throw ApiFailure(409, '这项任务已提交成功。请在“资料”关联官网作品链接后继续编辑，避免重复创建投稿');
    }
    if (task!['needs_latest'] == true && number(task!['post_id']) > 0) {
      throw ApiFailure(409, '请先载入官网最新内容，再继续编辑');
    }
    final missing = dynamicMissing(task!);
    if (missing.isNotEmpty) {
      throw ApiFailure(
        400,
        '请先补齐：${missing.map((k) => dynamicFieldNames[k]).join('、')}',
      );
    }
    task!['status'] = 'ready';
    save();
    final id = number(task!['post_id']);
    if (id > 0) {
      final p = object(
        (await widget.app.get('post/info', {
          'id': id,
          'include': 'user,categories:simple,tags',
          'exclude_view': 1,
        }))['data'],
      );
      if (!current) return;
      if (number(p['user_id']) != owner) throw ApiFailure(403, '只能修改自己的投稿');
      if (text(task!['version']).isNotEmpty &&
          task!['version'] != p['updated_at']) {
        throw ApiFailure(409, '官网内容已更新，请先“载入官网最新内容”后再继续修改');
      }
      task!['version'] = p['updated_at'];
      task!['baseline'] = postFingerprint(p);
      task!['oldStatus'] = p['status'];
      save();
    }
    await widget.onOpenDraft(
      text(task!['id']),
      dynamicEditorSnapshot(task!, owner),
      id,
    );
  });
  Future<void> loadPublished() async => perform(() async {
    if (task == null || number(task!['post_id']) <= 0) {
      throw ApiFailure(400, '任务还没有关联官网投稿编号');
    }
    final yes = await confirm(
      context,
      '载入官网最新内容？',
      '会把当前任务中的标题、正文、封面和分类替换为官网最新版本，对话历史保留。',
      action: '载入最新内容',
    );
    if (!yes || !current) return;
    final p = object(
      (await widget.app.get('post/info', {
        'id': number(task!['post_id']),
        'include': 'user,categories:simple,tags',
        'exclude_view': 1,
      }))['data'],
    );
    if (!current) return;
    if (number(p['user_id']) != owner) throw ApiFailure(403, '只能读取自己的未公开投稿');
    final fields = object(task!['fields']);
    fields['title'] = p['title'];
    fields['body_html'] = p['content'];
    fields['full_body'] = true;
    fields['cover'] = p['thumb'];
    fields['tags'] = rows(p['tags']).map((t) => text(t['name'])).join(', ');
    task!['fields'] = fields;
    task!['category_ids'] = rows(p['categories'])
        .map((c) => number(c['id']))
        .toList();
    task!['version'] = p['updated_at'];
    task!['baseline'] = postFingerprint(p);
    task!['oldStatus'] = p['status'];
    task!['desired_status'] = switch (text(p['status'])) {
      'draft' => 'draft',
      'publish' => 'publish',
      'future' => 'future',
      _ => 'pending',
    };
    task!['schedule'] = p['status'] == 'future'
        ? siteTimestamp(text(p['created_at']))
        : '';
    task!['status'] = 'collecting';
    task!['needs_latest'] = false;
    save();
    reply('已载入官网最新版本。可以发送修改要求，预览后确认保存。');
  });

  Future<void> associatePost() async {
    if (task == null) return;
    final input = TextEditingController();
    final id = await showDynamicTemplateDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('关联已提交作品'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: input,
            decoration: const InputDecoration(
              labelText: '官网作品链接或投稿编号',
              helperText: '在“投稿与管理”找到作品后复制链接，仅能关联自己的作品',
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
              final raw = input.text.trim(),
                  m = RegExp(
                    r'^https://(?:www\.)?cangku\.moe/archives/(\d+)(?:[/?#].*)?$',
                  ).firstMatch(raw);
              final value = int.tryParse(m?[1] ?? raw);
              if (value == null || value <= 0) {
                message(c, '请输入有效官网链接或编号');
                return;
              }
              Navigator.pop(c, value);
            },
            child: const Text('关联'),
          ),
        ],
      ),
    );
    input.dispose();
    if (id == null || !current) return;
    await perform(() async {
      final post = object(
        (await widget.app.get('post/info', {
          'id': id,
          'exclude_view': 1,
        }))['data'],
      );
      if (!current) return;
      if (number(post['user_id']) != owner) throw ApiFailure(403, '只能关联自己的作品');
      task!['post_id'] = id;
      task!['needs_latest'] = true;
      save();
      reply('已关联官网作品 #$id，请载入官网最新内容后继续编辑。');
    });
  }

  Widget panel({required Widget child}) => Material(
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: violet.withValues(alpha: .12)),
    ),
    child: Padding(padding: const EdgeInsets.all(18), child: child),
  );
  Widget templateList({bool sheet = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const IconBadge(Icons.auto_awesome_mosaic_rounded, size: 36),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '我的模板',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          IconButton(
            tooltip: '创建模板',
            onPressed: busy ? null : () => editTemplate(),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      const SizedBox(height: 12),
      for (final t in store!.templates)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: task != null && object(task!['template'])['id'] == t.id
                ? violet.withValues(alpha: .12)
                : Theme.of(context).colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              key: ValueKey('dynamic.template.${t.id}'),
              dense: true,
              contentPadding: const EdgeInsets.only(left: 12, right: 2),
              leading: Icon(switch (t.kind) {
                'game' => Icons.sports_esports_outlined,
                'asmr' => Icons.headphones_rounded,
                'comic' => Icons.menu_book_rounded,
                'animation' => Icons.movie_outlined,
                _ => Icons.auto_awesome_mosaic_outlined,
              }, color: violet),
              title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${aiTypes[t.kind]} · v${t.version}'),
              onTap: busy
                  ? null
                  : () {
                      createTask(t);
                      if (sheet) Navigator.pop(context);
                    },
              trailing: PopupMenuButton<String>(
                enabled: !busy,
                onSelected: (v) async {
                  if (v == 'edit') {
                    await editTemplate(template: t);
                    return;
                  }
                  if (v == 'ai') {
                    await refineTemplate(t);
                    return;
                  }
                  if (v == 'copy') {
                    await editTemplate(
                      learned: {
                        ...t.data,
                        'id': nonce(),
                        'name': '${t.name} · 副本',
                      },
                    );
                    return;
                  }
                  if (v == 'delete' &&
                      await confirm(
                        context,
                        '删除模板？',
                        '已存在的任务会保留各自使用的模板版本。',
                        action: '删除',
                      )) {
                    store!.deleteTemplate(t.id);
                    if (current) setState(() {});
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'ai',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AI 完善规则并预览'),
                        Text(
                          '参考来源前 1800 字，保存前请核对',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuItem(value: 'edit', child: Text('编辑与保存新版本')),
                  const PopupMenuItem(value: 'copy', child: Text('复制模板')),
                  const PopupMenuItem(value: 'delete', child: Text('删除模板')),
                ],
              ),
            ),
          ),
        ),
      OutlinedButton.icon(
        onPressed: busy ? null : learn,
        icon: const Icon(Icons.travel_explore_rounded),
        label: const Text('从网页学习模板'),
      ),
      const SizedBox(height: 24),
      Row(
        children: [
          const Icon(Icons.history_rounded, size: 19),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('继续任务', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          IconButton(
            tooltip: '刷新任务',
            onPressed: busy ? null : () => setState(() {}),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      for (final t in store!.tasks)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
            text(object(t['fields'])['title'], '未命名投稿'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${text(object(t['template'])['name'])} · ${statusLabel(text(t['status']))}',
          ),
          leading: Icon(
            task?['id'] == t['id']
                ? Icons.radio_button_checked
                : Icons.description_outlined,
            color: violet,
            size: 20,
          ),
          onTap: busy
              ? null
              : () {
                  selectTask(t);
                  if (sheet) Navigator.pop(context);
                },
          trailing: PopupMenuButton<String>(
            enabled: !busy,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'export', child: Text('导出任务与对话')),
              const PopupMenuItem(value: 'delete', child: Text('删除本机任务')),
            ],
            onSelected: (v) async {
              if (v == 'export') {
                final location = await getSaveLocation(
                  suggestedName: '星屿投稿任务-${text(t['id'])}.json',
                );
                if (location != null) {
                  await XFile.fromData(
                    utf8.encode(store!.exportTask(text(t['id']))),
                    mimeType: 'application/json',
                  ).saveTo(location.path);
                }
                return;
              }
              if (v == 'delete' &&
                  await confirm(
                    context,
                    '删除任务与对话？',
                    '同时删除此任务的本机记忆。官网投稿不会删除。',
                    action: '删除',
                  )) {
                store!.deleteTask(text(t['id']));
                if (task?['id'] == t['id']) {
                  task = null;
                  messages = [];
                }
                if (current) setState(() {});
              }
            },
          ),
        ),
    ],
  );
  Widget chat() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (task == null)
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const IconBadge(Icons.auto_awesome_rounded, size: 70),
                  const SizedBox(height: 18),
                  const Text(
                    '选个模板，开始一篇投稿',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '也可以直接描述：“按游戏分享模板整理这个 Steam 链接”。\n模板和任务在本机按账号保存，随时继续。',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: busy ? null : showTemplates,
                    icon: const Icon(Icons.dashboard_customize_outlined),
                    label: const Text('选择模板'),
                  ),
                ],
              ),
            ),
          ),
        )
      else
        Expanded(
          child: ListView.builder(
            controller: chatScroll,
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: messages.length,
            itemBuilder: (c, i) {
              final m = messages[i],
                  user = m['role'] == 'user',
                  tool = m['role'] == 'tool';
              return Align(
                alignment: user ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 720),
                  margin: const EdgeInsets.only(bottom: 12, left: 2, right: 2),
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: user
                        ? violet.withValues(alpha: .16)
                        : tool
                        ? Theme.of(c).colorScheme.surfaceContainerLow
                        : Theme.of(c).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: violet.withValues(alpha: .09)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            user
                                ? Icons.person_outline_rounded
                                : tool
                                ? Icons.link_rounded
                                : Icons.auto_awesome_rounded,
                            size: 16,
                            color: violet,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            user
                                ? '你'
                                : tool
                                ? '来源提取'
                                : '投稿助手',
                            style: const TextStyle(
                              fontSize: 12,
                              color: violet,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SelectableText(text(m['content'])),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      if (task != null && dynamicMissing(task!).isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final k in dynamicMissing(task!))
                ActionChip(
                  avatar: const Icon(
                    Icons.add_circle_outline_rounded,
                    size: 16,
                  ),
                  label: Text('补充${dynamicFieldNames[k]}'),
                  onPressed: busy ? null : () => setState(() => tab = 1),
                ),
            ],
          ),
        ),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: violet.withValues(alpha: .18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('dynamic.message'),
              controller: messageInput,
              minLines: 2,
              maxLines: 5,
              enabled: !busy,
              decoration: const InputDecoration(
                hintText: '发送作品链接、网盘链接，或描述修改要求…',
                border: InputBorder.none,
                filled: false,
              ),
              onSubmitted: (_) => unawaited(send()),
            ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 6,
              children: [
                if (task != null)
                  TextButton.icon(
                    onPressed: busy ? null : aiEdit,
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                    label: const Text('AI 按要求修改'),
                  ),
                FilledButton.icon(
                  onPressed: busy ? null : send,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_upward_rounded, size: 19),
                  label: Text(busy ? '处理中' : '发送'),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
  Future<void> showTemplates() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SizedBox(
        height: MediaQuery.sizeOf(c).height * .8,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: templateList(sheet: true),
        ),
      ),
    );
  }

  Widget field(String key, String label, {int lines = 1, String? helper}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 13),
        child: TextFormField(
          key: ValueKey(
            '${task!['id']}.$key.${text(object(task!['fields'])[key])}',
          ),
          initialValue: key == 'description' && preservesFullBody
              ? dynamicPlain(text(object(task!['fields'])['body_html']))
              : text(object(task!['fields'])[key]),
          maxLines: lines,
          enabled: !busy && !lockedBodyField(key),
          decoration: InputDecoration(
            labelText: label,
            helperText: lockedBodyField(key) ? '已保留完整正文，请通过对话或原编辑器修改' : helper,
            helperMaxLines: 2,
          ),
          onChanged: (v) {
            if (lockedBodyField(key)) return;
            final fields = object(task!['fields']);
            fields[key] = v;
            if (key == 'description') fields.remove('body_html');
            task!['fields'] = fields;
            task!['status'] = 'collecting';
            store!.saveTask(task!);
          },
          onFieldSubmitted: (_) => setState(() {}),
        ),
      );
  Widget materials() {
    if (task == null) return const Center(child: Text('先选择模板创建投稿任务'));
    final fields = object(task!['fields']);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 14),
      children: [
        if (preservesFullBody)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              '已保留官网完整正文。作品介绍可通过对话修改；正文图片、自购证明、下载信息和来源链接请在预览确认后进入原编辑器修改，保留已有排版。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 12,
              ),
            ),
          ),
        panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '投稿资料',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              field('title', '作品原标题'),
              field(
                'description',
                '作品介绍',
                lines: 5,
                helper: '留空时沿用来源正文；填入后使用这里的介绍',
              ),
              field('tags', '标签（逗号分隔）'),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : () => upload('cover'),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        text(fields['cover']).isEmpty ? '上传封面' : '替换封面',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (text(fields['cover']).isNotEmpty)
                    IconButton(
                      tooltip: '查看封面',
                      onPressed: () =>
                          showImage(context, url: text(fields['cover'])),
                      icon: const Icon(Icons.image_outlined),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              field('cover', '封面 HTTPS 地址'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('这是自购作品'),
                subtitle: const Text('启用后按模板要求上传证明'),
                value: fields['purchased'] == true,
                onChanged: busy || preservesFullBody
                    ? null
                    : (v) {
                        fields['purchased'] = v;
                        task!['fields'] = fields;
                        save();
                      },
              ),
              if (fields['purchased'] == true) ...[
                OutlinedButton.icon(
                  onPressed: busy || preservesFullBody
                      ? null
                      : () => upload('proof'),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(
                    text(fields['proof']).isEmpty ? '上传自购证明' : '替换自购证明',
                  ),
                ),
                const SizedBox(height: 12),
                field('proof', '自购证明 HTTPS 地址'),
              ],
              OutlinedButton.icon(
                onPressed: busy ? null : chooseCategories,
                icon: const Icon(Icons.category_outlined),
                label: Text(
                  '选择投稿分类 · ${(task!['category_ids'] as List? ?? []).length}',
                ),
              ),
              const SizedBox(height: 12),
              for (final url
                  in (fields['source_urls'] as List? ?? []).whereType<String>())
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.link_rounded),
                  title: Text(
                    url,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: '移除来源',
                    onPressed: busy || preservesFullBody
                        ? null
                        : () {
                            fields['source_urls'] =
                                (fields['source_urls'] as List)
                                    .where((v) => v != url)
                                    .toList();
                            task!['sources'] = rows(task!['sources'])
                                .where((s) => s['url'] != url)
                                .toList();
                            task!['fields'] = fields;
                            save();
                          },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: busy || preservesFullBody
                    ? null
                    : () => inputLink(false),
                icon: const Icon(Icons.add_link_rounded),
                label: const Text('添加作品来源'),
              ),
              TextButton.icon(
                onPressed: busy || preservesFullBody
                    ? null
                    : () => perform(extractSources),
                icon: const Icon(Icons.travel_explore_rounded),
                label: const Text('提取尚未加载的来源'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '下载信息',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              for (final d in rows(fields['downloads']))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cloud_download_outlined),
                  title: Text(text(d['name'])),
                  subtitle: Text(
                    text(d['url']),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: '删除下载链接',
                    onPressed: busy || preservesFullBody
                        ? null
                        : () {
                            fields['downloads'] = rows(fields['downloads'])
                                .where((v) => v['url'] != d['url'])
                                .toList();
                            task!['fields'] = fields;
                            save();
                          },
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: busy || preservesFullBody
                    ? null
                    : () => inputLink(true),
                icon: const Icon(Icons.add_link_rounded),
                label: const Text('添加下载信息'),
              ),
              const SizedBox(height: 12),
              field('code', '统一提取码（可选）'),
              field('password', '解压密码（可选）'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '排期与官网状态',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  '${task!['id']}.status.${text(task!['desired_status'], 'draft')}',
                ),
                initialValue: text(task!['desired_status'], 'draft'),
                items: [
                  const DropdownMenuItem(value: 'draft', child: Text('保存官网草稿')),
                  const DropdownMenuItem(value: 'pending', child: Text('提交审核')),
                  if (rows(widget.app.user?['permissions'])
                      .any((p) => p['name'] == 'publish_posts')) ...[
                    const DropdownMenuItem(
                      value: 'publish',
                      child: Text('直接发布'),
                    ),
                    const DropdownMenuItem(
                      value: 'future',
                      child: Text('官网定时发布'),
                    ),
                  ],
                  if (!rows(widget.app.user?['permissions'])
                          .any((p) => p['name'] == 'publish_posts') &&
                      ['publish', 'future'].contains(task!['desired_status']))
                    DropdownMenuItem(
                      value: text(task!['desired_status']),
                      child: Text(
                        task!['desired_status'] == 'publish'
                            ? '保持已发布状态'
                            : '保留官网排期',
                      ),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (v) {
                        task!['desired_status'] = v;
                        save();
                      },
              ),
              if (task!['desired_status'] == 'future')
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextFormField(
                    key: ValueKey(
                      '${task!['id']}.schedule.${text(task!['schedule'])}',
                    ),
                    initialValue: text(task!['schedule']),
                    decoration: const InputDecoration(
                      labelText: '上海时间 YYYY-MM-DD HH:mm:ss',
                      helperText: '最终在编辑器中确认，交由官网执行排期',
                    ),
                    onChanged: (v) {
                      task!['schedule'] = v;
                      store!.saveTask(task!);
                    },
                  ),
                ),
              if (number(task!['post_id']) > 0)
                TextButton.icon(
                  onPressed: busy ? null : loadPublished,
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('载入官网最新内容'),
                ),
              if (text(task!['submitted_at']).isNotEmpty &&
                  number(task!['post_id']) <= 0)
                OutlinedButton.icon(
                  onPressed: busy ? null : associatePost,
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('关联已提交作品，继续修改'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: busy ? null : previewDraft,
          icon: const Icon(Icons.preview_outlined),
          label: const Text('检查资料并预览'),
        ),
      ],
    );
  }

  Future<void> inputLink(bool download) async {
    if (preservesFullBody) {
      message(context, '已保留官网完整正文，请到原编辑器修改来源和下载信息');
      return;
    }
    final controller = TextEditingController();
    final value = await showDynamicTemplateDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(download ? '添加下载信息' : '添加作品来源'),
        content: SizedBox(
          width: 500,
          child: TextField(
            controller: controller,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: download
                  ? '粘贴网盘链接、提取码、解压密码'
                  : '粘贴 Steam、DLsite、游戏官网或其他公开网页链接',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty || !current) return;
    messageInput.text = download ? '下载链接：$value' : value;
    await send();
  }

  Widget preview() {
    if (task == null) return const Center(child: Text('先创建投稿任务'));
    final missing = dynamicMissing(task!);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 14),
      children: [
        if (text(task!['duplicate_note']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(text(task!['duplicate_note'])),
          ),
        for (final post in rows(task!['duplicate_results']).take(4))
          ListTile(
            dense: true,
            leading: const Icon(Icons.find_in_page_outlined),
            title: Text(
              text(post['title']),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.open_in_new_rounded, size: 18),
            onTap: () => openRoute(
              context,
              DeskRoute('post', '作品详情', id: number(post['id'])),
            ),
          ),
        for (final note
            in (task!['preflight_notes'] as List? ?? []).whereType<String>())
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '待核对：$note',
              style: TextStyle(color: Theme.of(context).colorScheme.secondary),
            ),
          ),
        if (missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              '还需补充：${missing.map((k) => dynamicFieldNames[k]).join('、')}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                dynamicTitle(task!),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 18),
              RichContent(
                ReaderDocument.parse(
                  dynamicBody(task!),
                  inlineResources: true,
                ).content,
                preloadVideos: false,
              ),
              const Divider(height: 28),
              const Text('确认后带入原投稿编辑器。最终提交、官网校验与冲突保护仍在编辑器完成。'),
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const Key('dynamic.preview.confirm'),
                onPressed: busy || missing.isNotEmpty ? null : openEditor,
                icon: const Icon(Icons.edit_note_rounded),
                label: Text(
                  number(task!['post_id']) > 0 ? '确认并继续编辑官网投稿' : '确认并继续投稿',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget memory() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: TextField(
          controller: searchInput,
          decoration: InputDecoration(
            labelText: '搜索模板或已提交作品',
            prefixIcon: const Icon(Icons.manage_search_rounded),
            suffixIcon: IconButton(
              tooltip: '搜索记忆',
              onPressed: () =>
                  setState(() => memories = store!.search(searchInput.text)),
              icon: const Icon(Icons.arrow_forward_rounded),
            ),
          ),
          onSubmitted: (v) => setState(() => memories = store!.search(v)),
        ),
      ),
      const Text('只检索模板和投稿摘要，完整对话留在各自任务中。下载密码、自购证明不进入记忆索引。'),
      const SizedBox(height: 10),
      Expanded(
        child: ListView(
          children: [
            for (final m in memories)
              Card(
                child: ListTile(
                  title: Text(text(m['title'])),
                  subtitle: Text(text(m['content'])),
                  leading: Icon(
                    m['kind'] == 'template'
                        ? Icons.auto_awesome_mosaic_outlined
                        : Icons.history_rounded,
                    color: violet,
                  ),
                  onTap: () {
                    final id = text(m['task_id']);
                    if (id.isNotEmpty) {
                      final t = store!.task(id);
                      if (t != null) {
                        selectTask(t);
                        setState(() => tab = 0);
                      }
                    } else {
                      final id = text(m['id']).replaceFirst('template.', '');
                      final t = store!.templates
                          .where((t) => t.id == id)
                          .firstOrNull;
                      if (t != null) {
                        createTask(t);
                        setState(() => tab = 0);
                      }
                    }
                  },
                  trailing: IconButton(
                    tooltip: '删除这条记忆',
                    onPressed: () async {
                      if (await confirm(
                        context,
                        '删除记忆？',
                        '任务和对话仍保留。',
                        action: '删除',
                      )) {
                        store!.deleteMemory(text(m['id']));
                        if (current) {
                          setState(
                            () => memories = store!.search(searchInput.text),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    if (store == null) {
      return Center(
        child: error.isEmpty
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error),
                  TextButton(onPressed: initialize, child: const Text('重试')),
                ],
              ),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    return Padding(
      padding: EdgeInsets.all(wide ? 24 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const IconBadge(Icons.auto_awesome_mosaic_rounded, size: 42),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '动态模板',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        task == null
                            ? '记住你的格式，接着你的创作'
                            : text(object(task!['template'])['name']),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                children: [
                  if (!wide)
                    TextButton.icon(
                      onPressed: busy ? null : showTemplates,
                      icon: const Icon(Icons.dashboard_customize_outlined),
                      label: const Text('模板与任务'),
                    ),
                  IconButton(
                    tooltip: 'AI 设置',
                    onPressed: busy ? null : settings,
                    icon: const Icon(Icons.tune_rounded),
                  ),
                  if (task != null)
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : previewDraft,
                      icon: const Icon(Icons.preview_outlined, size: 18),
                      label: const Text('预览'),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide) ...[
                  SizedBox(
                    width: 270,
                    child: SingleChildScrollView(
                      child: panel(child: templateList()),
                    ),
                  ),
                  const SizedBox(width: 20),
                ],
                Expanded(
                  child: Column(
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(
                              value: 0,
                              label: Text('对话'),
                              icon: Icon(Icons.chat_bubble_outline_rounded),
                            ),
                            ButtonSegment(
                              value: 1,
                              label: Text('资料'),
                              icon: Icon(Icons.folder_open_rounded),
                            ),
                            ButtonSegment(
                              value: 2,
                              label: Text('预览'),
                              icon: Icon(Icons.preview_outlined),
                            ),
                            ButtonSegment(
                              value: 3,
                              label: Text('记忆'),
                              icon: Icon(Icons.manage_search_rounded),
                            ),
                          ],
                          selected: {tab},
                          onSelectionChanged: (v) {
                            setState(() {
                              tab = v.first;
                              if (tab == 3) {
                                memories = store!.search(searchInput.text);
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: switch (tab) {
                          1 => materials(),
                          2 => preview(),
                          3 => memory(),
                          _ => chat(),
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String statusLabel(String status) => switch (status) {
  'collecting' => '待补资料',
  'ready' => '待确认',
  'pending' => '待审核',
  'publish' => '已发布',
  'future' => '已排期',
  'website_draft' => '官网草稿',
  _ => status,
};

/// Wait until the reverse transition has released the dialog subtree before
/// callers dispose its locally owned text controllers.
Future<T?> showDynamicTemplateDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final navigator = Navigator.of(context);
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
  );
  final value = await navigator.push<T>(route);
  await route.completed;
  return value;
}
