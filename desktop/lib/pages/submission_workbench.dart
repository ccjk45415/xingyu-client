import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;

import '../core/ai.dart';
import '../core/reader.dart';
import '../core/api.dart';
import '../core/state.dart';
import '../core/submission_guidance.dart';
import '../core/submission_workbench.dart';
import '../core/editor_tools.dart';
import '../ui/ai_panels.dart';
import '../ui/shared.dart';
import '../ui/editor_templates.dart';

class WorkbenchChange {
  final String body;
  final List<Json> metadata;
  const WorkbenchChange(this.body, {this.metadata = const []});
}

Future<WorkbenchChange?> showSubmissionWorkbench(
  BuildContext context, {
  required AppState app,
  required String title,
  required String body,
  List<Json> sources = const [],
  Set<int> categories = const {},
  String kind = 'other',
  String cover = '',
  String task = 'command',
  EditorSnapshot? selection,
  int postId = 0,
}) {
  final scope = context.getInheritedWidgetOfExactType<DeskScope>();
  return showDialog<WorkbenchChange>(
    context: context,
    barrierDismissible: false,
    builder: (c) {
      final panel = SubmissionWorkbench(
        app: app,
        title: title,
        body: body,
        sources: sources,
        categories: categories,
        kind: kind,
        cover: cover,
        initialTask: task,
        selection: selection,
        postId: postId,
      );
      return scope == null
          ? panel
          : DeskScope(
              app: app,
              open: (route) {
                Navigator.pop(c);
                scope.open(route);
              },
              child: panel,
            );
    },
  );
}

const toolNames = {
  ...workbenchTasks,
  'duplicates': '疑似重复投稿',
  'download': '拆分下载信息',
  'habits': '个人投稿习惯',
};
const toolIcons = <String, IconData>{
  'metadata': Icons.dataset_outlined,
  'preflight': Icons.fact_check_outlined,
  'command': Icons.auto_awesome_rounded,
  'selection': Icons.text_fields_rounded,
  'review': Icons.rule_folder_outlined,
  'layout': Icons.auto_fix_high_outlined,
  'proofread': Icons.spellcheck_rounded,
  'duplicates': Icons.find_in_page_outlined,
  'download': Icons.add_link_rounded,
  'habits': Icons.tune_rounded,
};
const toolHints = {
  'metadata': '提取作者、社团、平台、日期等，只采用有原文依据的资料',
  'preflight': '先检查官网规范，再按需进行 AI 内容检查',
  'command': '描述你要修改的内容，先看修改结果再应用',
  'selection': '只修改打开助手前选中的文字，其他内容保持原样',
  'review': '粘贴审核意见，逐项核对并生成修改建议',
  'layout': '识别段落层级与列表，保留原文和图片链接',
  'proofread': '对照来源原文检查漏译、数字和事实差异',
  'duplicates': '按作品编号与名称搜索官网，结果仅作为疑似重复提示',
  'download': '粘贴分享信息，核对地址、提取码和解压密码后插入官网下载模块',
  'habits': '保存本机排版偏好，按账号区分；不会记住资源密码或自购证明',
};

class SubmissionWorkbench extends StatefulWidget {
  final AppState app;
  final String title, body, kind, cover, initialTask;
  final List<Json> sources;
  final Set<int> categories;
  final EditorSnapshot? selection;
  final int postId;
  final bool embedded;
  final ValueChanged<WorkbenchChange>? onApply;
  final VoidCallback? onClose;
  const SubmissionWorkbench({
    super.key,
    required this.app,
    required this.title,
    required this.body,
    this.sources = const [],
    this.categories = const {},
    this.kind = 'other',
    this.cover = '',
    this.initialTask = 'command',
    this.selection,
    this.postId = 0,
    this.embedded = false,
    this.onApply,
    this.onClose,
  });
  @override
  State<SubmissionWorkbench> createState() => _SubmissionWorkbenchState();
}

class _SubmissionWorkbenchState extends State<SubmissionWorkbench> {
  final instruction = TextEditingController(),
      sourceText = TextEditingController(),
      downloadText = TextEditingController();
  final address = TextEditingController(),
      keyInput = TextEditingController(),
      model = TextEditingController();
  final io = AiTransport();
  late final duplicateQuery = TextEditingController(
    text: duplicateQueries(
      widget.title,
      widget.sources.map((s) => text(s['url'])),
    ).join('\n'),
  );
  late String task = widget.initialTask;
  late final int owner = widget.app.uid,
      accountGeneration = widget.app.generation;
  late List<Json> sources = [...widget.sources];
  bool busy = false, custom = false, configLoaded = false, showTools = false;
  String error = '', proposedBody = '';
  List<String> notes = [];
  List<Json> metadata = [], duplicates = [];
  Set<int> checkedFields = {};
  int font = 17;
  double lineHeight = 1.8;
  bool compactParagraphs = false;
  bool get current =>
      mounted &&
      widget.app.uid == owner &&
      widget.app.generation == accountGeneration;
  @override
  void initState() {
    super.initState();
    final pref = widget.app.submissionHabits;
    font = number(pref['font']).clamp(13, 24);
    if (pref['font'] == null) font = 17;
    lineHeight =
        (pref['lineHeight'] as num?)?.toDouble().clamp(1.4, 2.4) ?? 1.8;
    compactParagraphs = pref['compact'] == true;
    loadConfig();
  }

  Future<void> loadConfig() async {
    try {
      final raw = await widget.app.site.storage.read(key: 'ai.$owner');
      if (!current) return;
      final config = raw == null
          ? <String, dynamic>{}
          : object(jsonDecode(raw));
      setState(() {
        custom = config['custom'] == true;
        address.text = text(config['address']);
        keyInput.text = text(config['key']);
        model.text = text(config['model']);
        configLoaded = true;
      });
    } catch (_) {
      if (current) {
        setState(() {
          configLoaded = true;
          error = '无法读取 AI 配置，请重新填写';
        });
      }
    }
  }

  @override
  void dispose() {
    io.close();
    for (final c in [
      duplicateQuery,
      instruction,
      sourceText,
      downloadText,
      address,
      keyInput,
      model,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void reset(String next) => setState(() {
    task = next;
    showTools = false;
    error = '';
    proposedBody = '';
    notes = [];
    metadata = [];
    checkedFields = {};
    duplicates = [];
  });
  Future<void> perform(Future<void> Function() work) async {
    if (!current || busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await work();
    } catch (e) {
      if (current) {
        setState(
          () => error = e is ApiFailure ? e.message : '处理失败或网络超时，原稿已保留，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<Json> get actualSources => [
    for (final s in sources)
      {
        'url': text(s['url']),
        'text': '${text(s['facts'])}\n${text(s['text'])}'.trim(),
      },
    if (sourceText.text.trim().isNotEmpty)
      {'url': '', 'text': sourceText.text.trim()},
  ];
  String get target {
    final selected = widget.selection;
    if (task == 'selection') {
      if (selected == null || selected.a == selected.b) {
        throw ApiFailure(400, '请先在正文中选中文字，再打开“局部处理”');
      }
      return selected.text.substring(selected.a, selected.b);
    }
    return widget.body;
  }

  Future<void> localCheck() async {
    final guide = await SubmissionGuidance.load();
    if (!current) return;
    final issues = guide.check(
      title: widget.title,
      body: widget.body,
      selected: widget.categories,
      tree: widget.app.categories,
      kind: widget.kind,
    );
    setState(
      () => notes = [
        ...issues.map((e) => e.message),
        ...extraPreflight(
          widget.title,
          widget.body,
          cover: widget.cover,
          sourceUrls: sources.map((s) => text(s['url'])),
        ),
        if (issues.isEmpty) '官网格式基础检查未发现缺项。',
        '检查结果仅作辅助，资源可用性、权利和官网最新规则仍需人工确认。',
      ],
    );
  }

  Future<void> localMetadata() async {
    final values = structuredSourceFields(actualSources);
    if (values.isEmpty) throw ApiFailure(422, '未找到带明确字段名的资料，可使用 AI 整理或粘贴作品资料表');
    setState(() {
      metadata = values;
      checkedFields = {for (var i = 0; i < values.length; i++) i};
      notes = ['已提取带明确标签的作品资料，请核对原文依据。'];
    });
  }

  Future<void> findDuplicates() async {
    final lines = duplicateQuery.text
        .split(RegExp(r'[\r\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (lines.isEmpty) throw ApiFailure(400, '请在上方填写作品名称或 RJ 号');
    if (lines.length > 4) throw ApiFailure(400, '每次最多检索 4 个关键词，请每行填写一个');
    final queries = lines
        .expand((line) => duplicateQueries(line, const []))
        .toSet()
        .toList();
    if (queries.length > 4) throw ApiFailure(400, '作品编号与名称合计最多检索 4 项，请减少关键词');
    final found = <int, Json>{};
    for (final q in queries) {
      final value = await widget.app.get('post/search', {
        'search': q,
        'page': 1,
        'per_page': 12,
        'simple': 1,
        'include': 'user,categories:simple',
      });
      if (!current) return;
      for (final p in rows(value['data'])) {
        final id = number(p['id']);
        if (id > 0 && id != widget.postId) found[id] = {...p, '_query': q};
      }
    }
    setState(() {
      duplicates = found.values.toList();
      notes = [
        '检索：${queries.join('、')}',
        found.isEmpty
            ? '当前搜索结果中未找到疑似重复；这不代表官网一定没有相同作品。'
            : '找到 ${found.length} 条候选，请核对版本、编号与内容后决定是否投稿。',
      ];
    });
  }

  Future<void> runAi() async {
    if (!workbenchTasks.containsKey(task)) return;
    if (['command', 'selection', 'review'].contains(task) &&
        instruction.text.trim().isEmpty) {
      throw ApiFailure(400, '请填写修改要求或审核意见');
    }
    if (task == 'metadata' && actualSources.isEmpty) {
      throw ApiFailure(400, '请先提取来源或粘贴作品资料');
    }
    if (task == 'proofread' && actualSources.isEmpty) {
      throw ApiFailure(400, '请提供原文资料，才能进行翻译质量复核');
    }
    if (task == 'command') {
      final local = localSubmissionCommand(widget.body, instruction.text);
      if (local != null) {
        setState(() {
          proposedBody = local;
          notes = ['已在本机生成排版修改，不调用 AI；确认后应用。'];
        });
        return;
      }
    }
    if (task == 'preflight') await localCheck();
    if (!current) return;
    final localNotes = task == 'preflight' ? [...notes] : <String>[];
    final document = WorkDocument(target);
    if (task != 'metadata' && document.segments.isEmpty) {
      throw ApiFailure(400, '当前没有可以处理的正文文字');
    }
    final request = <String, dynamic>{
      'request_id': nonce(),
      'task': task,
      'title': widget.title,
      'instruction': instruction.text.trim(),
      'segments': document.segments,
      'sources': actualSources,
    };
    if (utf8.encode(jsonEncode(request)).length > (custom ? 200000 : 12000)) {
      throw ApiFailure(
        413,
        custom
            ? '本次资料过多，请选中较小的段落分次处理；不会截断原稿'
            : '内置工具单次资料上限为 12 KB，请使用局部处理或减少原文资料；不会截断原稿',
      );
    }
    Json result;
    if (custom) {
      aiEndpoint(address.text);
      if (model.text.trim().isEmpty || keyInput.text.trim().isEmpty) {
        throw ApiFailure(400, '请填写自定义模型与 API Key');
      }
      await widget.app.site.storage.write(
        key: 'ai.$owner',
        value: jsonEncode({
          'custom': true,
          'address': address.text.trim(),
          'key': keyInput.text.trim(),
          'model': model.text.trim(),
        }),
      );
      if (!current) return;
      final response = await io.json(
        aiEndpoint(address.text),
        token: keyInput.text.trim(),
        body: {
          'model': model.text.trim(),
          'stream': false,
          'max_tokens': 8000,
          'messages': [
            {'role': 'system', 'content': workbenchSystem},
            {'role': 'user', 'content': jsonEncode(request)},
          ],
        },
      );
      final choices = rows(response['choices']);
      if (choices.isEmpty) throw ApiFailure(502, '模型没有返回处理结果');
      result = parseWorkbench(
        object(choices.first['message'])['content'],
        request,
      );
    } else {
      if (!widget.app.verified) {
        if (!mounted) return;
        final yes = await confirm(
          context,
          '认证并使用内置 AI？',
          '当前登录会话将交给星屿服务向官网核验，不保存会话。所选正文与来源文字将交给 Cloudflare AI 处理。每次工具调用与翻译共用每日额度，开始处理即计次。',
          action: '认证并继续',
        );
        if (!yes || !current) return;
        await widget.app.enableIdentity();
      }
      if (!current) return;
      final response = await io.json(
        Uri.parse('$serviceOrigin/ai/v3/task'),
        token: widget.app.token,
        body: request,
        builtin: true,
        timeout: const Duration(seconds: 180),
      );
      result = parseWorkbench(response['result'], request);
    }
    if (!current) return;
    final edits = rows(result['edits']);
    var next = edits.isEmpty
        ? ''
        : document.apply(edits, layoutOnly: task == 'layout');
    if (next.isNotEmpty && task == 'selection') {
      final selected = widget.selection!;
      next = widget.body.replaceRange(selected.a, selected.b, next);
    }
    setState(() {
      proposedBody = next;
      metadata = rows(result['metadata']);
      checkedFields = {for (var i = 0; i < metadata.length; i++) i};
      notes = [
        ...localNotes,
        if (task == 'proofread')
          ...translationChecks([
            ...sources,
            if (sourceText.text.trim().isNotEmpty) {'text': sourceText.text},
          ], widget.body),
        ...(result['notes'] as List).map((n) => text(n)),
        if (edits.isEmpty &&
            metadata.isEmpty &&
            (result['notes'] as List).isEmpty)
          '未提出修改，原稿保持原样。',
      ];
    });
  }

  Future<void> makeDownloads() async {
    final links = splitDownloadMaterial(downloadText.text);
    if (links.isEmpty) throw ApiFailure(400, '没有识别到有效下载地址');
    final cards = links
        .map(
          (l) => downloadTemplate(
            title: widget.title.trim().isEmpty ? '资源下载' : widget.title,
            code: l.code,
            password: l.password,
            links: [(name: l.name, url: l.url)],
          ),
        )
        .join('\n');
    setState(() {
      proposedBody = '${removeEmptyListPlaceholders(widget.body)}\n$cards';
      notes = [
        for (final l in links)
          '${l.name}\n${l.url}\n提取码：${l.code.isEmpty ? '未识别' : l.code}\n解压密码：${l.password.isEmpty ? '未识别' : l.password}',
        '以上信息只在本机拆分，不会调用 AI。请核对每个链接对应的密码。',
      ];
    });
  }

  String habitsBody() => applySubmissionHabits(widget.body, {
    'font': font,
    'lineHeight': lineHeight,
    'compact': compactParagraphs,
  });
  Future<void> saveHabits() async {
    await widget.app.setSubmissionHabits({
      'font': font,
      'lineHeight': lineHeight,
      'compact': compactParagraphs,
      'enabled': true,
    });
    if (current) {
      setState(() => notes = ['已保存本机投稿习惯。新导入的 AI 正文会采用这些排版；既有正文需手动应用。']);
    }
  }

  void applyResult() {
    if (!current || busy) return;
    final chosen = [
      for (var i = 0; i < metadata.length; i++)
        if (checkedFields.contains(i)) metadata[i],
    ];
    var body = proposedBody.isEmpty ? widget.body : proposedBody;
    if (chosen.isNotEmpty) {
      body +=
          '\n<h3>作品资料</h3><ul>${chosen.map((f) => '<li>${aiEscape(text(f['label']))}：${aiEscape(text(f['value']))}</li>').join()}</ul>';
    }
    if (body.length > 1000000) {
      setState(() => error = '修改后超出编辑器容量，原稿已保留');
      return;
    }
    final change = WorkbenchChange(body, metadata: chosen);
    if (widget.onApply != null) {
      widget.onApply!(change);
    } else {
      Navigator.pop(context, change);
    }
  }

  Widget aiService() => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: Text(custom ? '自定义 AI · 点击配置' : '内置 AI · 共用每日额度'),
    leading: Icon(
      custom ? Icons.dns_outlined : Icons.cloud_outlined,
      color: violet,
    ),
    children: [
      SwitchListTile(
        title: const Text('使用自定义 AI'),
        subtitle: const Text('沿用投稿助手的模型配置，密钥本机加密保存'),
        value: custom,
        onChanged: busy ? null : (v) => setState(() => custom = v),
      ),
      if (custom) ...[
        TextField(
          controller: address,
          decoration: aiInput('API 地址', icon: Icons.link_rounded),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: keyInput,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: aiInput('API Key', icon: Icons.key_outlined),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: model,
          decoration: aiInput('模型名称', icon: Icons.memory_outlined),
        ),
      ] else
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            '工具调用与翻译共用个人每天 3 次、全体每天 16 个处理单位；失败不自动重试。本机检查、检索和拆分不消耗 AI 次数。',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
        ),
    ],
  );
  Widget tools() {
    if (MediaQuery.sizeOf(context).width >= 640) return toolsGrid();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: violet.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(toolIcons[task], color: violet, size: 21),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  toolNames[task]!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () => setState(() => showTools = !showTools),
                icon: Icon(
                  showTools ? Icons.expand_less : Icons.grid_view_rounded,
                  size: 17,
                ),
                label: Text(showTools ? '收起' : '切换工具'),
              ),
            ],
          ),
        ),
        if (showTools)
          Padding(padding: const EdgeInsets.only(top: 10), child: toolsGrid()),
      ],
    );
  }

  Widget toolsGrid() => LayoutBuilder(
    builder: (c, size) {
      final columns = size.maxWidth >= 800
          ? 5
          : size.maxWidth >= 500
          ? 3
          : 2;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in toolNames.entries)
            SizedBox(
              width: (size.maxWidth - (columns - 1) * 8) / columns,
              child: Material(
                color: task == entry.key
                    ? violet.withValues(alpha: .13)
                    : Theme.of(c).colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: violet.withValues(
                      alpha: task == entry.key ? .5 : .15,
                    ),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: busy ? null : () => reset(entry.key),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 14,
                    ),
                    child: Column(
                      children: [
                        Icon(toolIcons[entry.key], color: violet, size: 23),
                        const SizedBox(height: 8),
                        Text(
                          entry.value,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
  Widget taskPanel() => AiPanel(
    title: toolNames[task]!,
    subtitle: toolHints[task]!,
    icon: toolIcons[task]!,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (task == 'habits') ...[
          Text('正文字号 $font px'),
          Slider(
            value: font.toDouble(),
            min: 13,
            max: 24,
            divisions: 11,
            onChanged: busy ? null : (v) => setState(() => font = v.round()),
          ),
          Text('段落行高 ${lineHeight.toStringAsFixed(1)}'),
          Slider(
            value: lineHeight,
            min: 1.4,
            max: 2.4,
            divisions: 10,
            onChanged: busy ? null : (v) => setState(() => lineHeight = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('紧凑段间距'),
            value: compactParagraphs,
            onChanged: busy
                ? null
                : (v) => setState(() => compactParagraphs = v),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: busy ? null : () => perform(saveHabits),
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存习惯'),
              ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        proposedBody = habitsBody();
                        notes = ['仅调整段落字号、行高和间距。'];
                      }),
                icon: const Icon(Icons.preview_outlined),
                label: const Text('预览应用到正文'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => perform(() async {
                        await widget.app.setSubmissionHabits({});
                        if (current) setState(() => notes = ['已恢复默认投稿习惯。']);
                      }),
                child: const Text('恢复默认'),
              ),
            ],
          ),
        ] else if (task == 'download') ...[
          TextField(
            controller: downloadText,
            minLines: 4,
            maxLines: 9,
            decoration: aiInput(
              '分享信息',
              hint: '粘贴网盘链接、提取码和解压密码',
              icon: Icons.content_paste_rounded,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: busy ? null : () => perform(makeDownloads),
            icon: const Icon(Icons.add_link_rounded),
            label: const Text('本机拆分并预览'),
          ),
        ] else if (task == 'duplicates') ...[
          TextField(
            key: const Key('ai.duplicate.query'),
            controller: duplicateQuery,
            enabled: !busy,
            minLines: 2,
            maxLines: 4,
            maxLength: 600,
            decoration: aiInput(
              '作品名 / RJ 号',
              hint: '例如：RJ01699082 或作品原名，每行一个',
              helper: '自动带入标题和来源编号，可在这里修改。最多 4 项，仅用于检索，不会修改投稿标题。',
              icon: Icons.manage_search_rounded,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: busy ? null : () => perform(findDuplicates),
            icon: const Icon(Icons.search_rounded),
            label: const Text('检索官网投稿'),
          ),
        ] else ...[
          if (['command', 'selection', 'review'].contains(task)) ...[
            if (task == 'selection')
              AiNotice(
                widget.selection == null ||
                        widget.selection!.a == widget.selection!.b
                    ? '尚未选择文字。请返回正文选中需要处理的内容，再打开 AI 投稿助手。'
                    : '已选 ${(widget.selection!.b - widget.selection!.a)} 个源码字符，仅修改选区。',
                icon: Icons.text_fields_rounded,
              ),
            const SizedBox(height: 10),
            TextField(
              controller: instruction,
              minLines: 2,
              maxLines: 6,
              maxLength: 1000,
              decoration: aiInput(
                task == 'review' ? '审核意见' : '修改要求',
                hint: task == 'review'
                    ? '粘贴需要处理的退稿意见'
                    : '例如：修正错别字；把介绍图片放到正文后；清理空段落',
                icon: Icons.edit_note_rounded,
              ),
            ),
          ],
          if (['metadata', 'proofread', 'preflight', 'review'].contains(task))
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('来源资料 · 已带入 ${sources.length} 个来源'),
              subtitle: const Text('可补充原文，未知事实留空'),
              children: [
                TextField(
                  controller: sourceText,
                  minLines: 3,
                  maxLines: 8,
                  decoration: aiInput(
                    '补充来源原文',
                    helper: '仅粘贴公开作品资料，不填写密码、订单或会话',
                  ),
                ),
              ],
            ),
          if (task == 'preflight') ...[
            OutlinedButton.icon(
              onPressed: busy ? null : () => perform(localCheck),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('本机规范检查 · 免费'),
            ),
            const SizedBox(height: 8),
          ],
          if (task == 'metadata') ...[
            OutlinedButton.icon(
              onPressed: busy ? null : () => perform(localMetadata),
              icon: const Icon(Icons.dataset_outlined),
              label: const Text('提取明确字段 · 免费'),
            ),
            const SizedBox(height: 8),
          ],
          if (task == 'proofread') ...[
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () => setState(
                      () => notes = translationChecks([
                        ...sources,
                        if (sourceText.text.trim().isNotEmpty)
                          {'text': sourceText.text},
                      ], widget.body),
                    ),
              icon: const Icon(Icons.numbers_rounded),
              label: const Text('本机数字与图片检查'),
            ),
            const SizedBox(height: 8),
          ],
          aiService(),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: busy || !configLoaded ? null : () => perform(runAi),
            icon: const Icon(Icons.auto_awesome_rounded),
            label: Text(
              '使用${custom ? '自定义' : '内置'} AI ${['preflight', 'proofread'].contains(task) ? '检查' : '处理'}',
            ),
          ),
        ],
      ],
    ),
  );
  Widget results() => AiPanel(
    title: '结果与修改预览',
    subtitle: '确认后带回编辑器，仍可撤销；不会自动提交网站',
    icon: Icons.preview_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SelectableText(
              '• $note',
              style: const TextStyle(fontSize: 13, height: 1.7),
            ),
          ),
        for (var i = 0; i < metadata.length; i++)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text('${metadata[i]['label']}：${metadata[i]['value']}'),
            subtitle: Text(
              '来源 ${number(metadata[i]['source_id']) + 1} · ${metadata[i]['evidence']}',
              style: const TextStyle(fontSize: 11),
            ),
            value: checkedFields.contains(i),
            onChanged: busy
                ? null
                : (v) => setState(() {
                    if (v == true) {
                      checkedFields.add(i);
                    } else {
                      checkedFields.remove(i);
                    }
                  }),
          ),
        for (final p in duplicates)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.article_outlined, color: violet),
            title: Text(text(p['title']), maxLines: 3),
            subtitle: Text('编号 ${p['id']} · 命中 ${p['_query']}'),
            trailing: IconButton(
              tooltip: '复制官网地址',
              onPressed: () => copy(context, '$siteOrigin/archives/${p['id']}'),
              icon: const Icon(Icons.copy_outlined),
            ),
            onTap: () => openLink(context, '$siteOrigin/archives/${p['id']}'),
          ),
        if (proposedBody.isNotEmpty) ...[
          ExpansionTile(
            title: const Text('修改前 · 点击对照'),
            tilePadding: EdgeInsets.zero,
            children: [
              RichContent(
                ReaderDocument.parse(
                  widget.body,
                  inlineResources: true,
                ).content,
                fontSize: 14,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('修改后', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          RichContent(
            ReaderDocument.parse(proposedBody, inlineResources: true).content,
            fontSize: 14,
          ),
        ],
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 640;
    final panel = SizedBox(
      width: 1120,
      height: MediaQuery.sizeOf(context).height * .9,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.embedded)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const IconBadge(Icons.auto_awesome_rounded),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '投稿工具箱',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text('让资料更完整，让修改更轻松', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      io.close();
                      Navigator.pop(context);
                    },
                    tooltip: '关闭工具箱',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              key: const Key('workbench.scroll'),
              primary: false,
              padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  tools(),
                  const SizedBox(height: 16),
                  taskPanel(),
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: AiNotice(error, icon: Icons.error_outline_rounded),
                    ),
                  if (notes.isNotEmpty ||
                      proposedBody.isNotEmpty ||
                      metadata.isNotEmpty ||
                      duplicates.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: results(),
                    ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
          if (busy) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: widget.onClose ?? () => Navigator.pop(context),
                  child: Text(widget.embedded ? '返回资料与翻译' : '返回编辑'),
                ),
                FilledButton.icon(
                  onPressed:
                      busy ||
                          !current ||
                          (proposedBody.isEmpty && checkedFields.isEmpty)
                      ? null
                      : applyResult,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('应用已确认结果'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (widget.embedded) return panel;
    return Dialog(
      insetPadding: EdgeInsets.all(compact ? 10 : 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: panel,
    );
  }
}

bool insidePurchaseProof(dom.Node element) {
  dom.Node? parent = element;
  while (parent != null) {
    if (parent is dom.Element &&
        parent.attributes.containsKey('data-xingyu-purchase-proof')) {
      return true;
    }
    parent = parent.parent;
  }
  return false;
}

String applySubmissionHabits(String source, Json habits) {
  if (habits.isEmpty) return source;
  final doc = html.parseFragment(source),
      font = number(habits['font']).clamp(13, 24);
  final height =
      (habits['lineHeight'] as num?)?.toDouble().clamp(1.4, 2.4) ?? 1.8;
  for (final p in doc.querySelectorAll('p,li,blockquote')) {
    if (insidePurchaseProof(p) || p.querySelector('img') != null) {
      continue;
    }
    var style = p.attributes['style'] ?? '';
    style = style.replaceAll(
      RegExp(
        r'(?:font-size|line-height|margin-bottom)\s*:[^;]*(?:;|$)',
        caseSensitive: false,
      ),
      '',
    );
    p.attributes['style'] =
        '$style;font-size:${font}px;line-height:$height;margin-bottom:${habits['compact'] == true ? 8 : 16}px';
  }
  return doc.outerHtml;
}
