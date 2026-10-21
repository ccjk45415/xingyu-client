import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/ai.dart';
import '../core/translation.dart';

import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../core/api.dart';
import '../core/state.dart';
import '../ui/shared.dart';

class AiImport {
  final AiDraft draft;
  final bool title, body, tags, cover, append;
  AiImport(
    this.draft,
    this.title,
    this.body,
    this.tags,
    this.cover,
    this.append,
  );
}

Future<AiImport?> showAiAssistant(BuildContext context) {
  final app = stateOf(context);
  return showDialog<AiImport>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AiAssistantDialog(app),
  );
}

class AiAssistantDialog extends StatefulWidget {
  final AppState app;
  const AiAssistantDialog(this.app, {super.key});
  @override
  State<AiAssistantDialog> createState() => _AiAssistantDialogState();
}

class _AiAssistantDialogState extends State<AiAssistantDialog> {
  final links = TextEditingController(),
      material = TextEditingController(),
      address = TextEditingController(),
      keyInput = TextEditingController(),
      model = TextEditingController();
  AiTransport transport = AiTransport();
  bool custom = false,
      busy = false,
      loaded = false,
      keepOriginal = false,
      importTitle = true,
      importBody = true,
      importTags = false,
      importCover = false,
      append = true;
  String type = 'auto', status = '';
  int run = 0;
  late final int owner = widget.app.uid, generation = widget.app.generation;
  List<Json> sources = [];
  AiDraft? draft;
  bool get current =>
      mounted && widget.app.uid == owner && widget.app.generation == generation;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final raw = await widget.app.site.storage.read(key: 'ai.$owner');
      if (!current) return;
      final cfg = raw == null ? <String, dynamic>{} : object(jsonDecode(raw));
      setState(() {
        custom = cfg['custom'] == true;
        address.text = text(cfg['address']);
        keyInput.text = text(cfg['key']);
        model.text = text(cfg['model']);
        loaded = true;
      });
    } catch (_) {
      if (current) {
        setState(() {
          loaded = true;
          status = '无法读取加密配置，请重新填写';
        });
      }
    }
  }

  Future<void> save({bool validate = true}) async {
    if (!current) throw ApiFailure(409, '账号已切换');
    if (validate && custom) {
      aiEndpoint(address.text);
      if (model.text.trim().isEmpty) throw ApiFailure(400, '请填写模型名');
    }
    await widget.app.site.storage.write(
      key: 'ai.$owner',
      value: jsonEncode({
        'custom': custom,
        'address': address.text.trim(),
        'key': keyInput.text.trim(),
        'model': model.text.trim(),
      }),
    );
  }

  Future<void> action(Future<void> Function() work) async {
    final id = ++run;
    setState(() {
      busy = true;
      status = '正在处理；介绍将逐段翻译，请勿重复生成…';
    });
    try {
      await work();
    } catch (e) {
      if (current &&
          id == run &&
          !custom &&
          e is ApiFailure &&
          e.status == 401) {
        widget.app.expireIdentity();
        await widget.app.site.storage.delete(key: 'chat.$owner');
      }
      if (current && id == run) {
        setState(
          () => status = e is ApiFailure ? e.message : '操作失败或连接超时，请检查网络后重试',
        );
      }
    } finally {
      if (current && id == run) setState(() => busy = false);
    }
  }

  void cancel() {
    run++;
    transport.close();
    transport = AiTransport();
    setState(() {
      busy = false;
      status = '已取消。本次内置生成若已开始，仍计入额度；可用“恢复上次结果”读取，不重复扣次。';
    });
  }

  Future<void> verify() async {
    if (widget.app.verified) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('认证仓库账号'),
        content: const Text(
          '内置AI按仓库UID分配额度。将当前登录会话交给星屿服务向官网验证，不保存官网密码或会话。你选择的公开介绍会交给Cloudflare AI处理，草稿缓存1小时。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('认证并继续'),
          ),
        ],
      ),
    );
    if (yes != true || !current) throw ApiFailure(499, '已取消认证');
    await widget.app.enableIdentity();
  }

  Json? previous;
  Future<void> generate({bool recover = false}) async {
    final job = run, io = transport;
    await save(validate: !keepOriginal);
    if (!current || run != job) return;
    if (!recover) {
      if (sources.isEmpty) throw ApiFailure(400, '请先提取链接，或填链接并使用粘贴素材');
      final data = translationRequest(sources, material.text, type, nonce());
      if (!custom && !keepOriginal) {
        final planned = rows(jsonDecode(jsonEncode(data['sources'])));
        if (material.text.trim().isNotEmpty) {
          final blocks = rows(planned.first['blocks']);
          blocks.add({'kind': 'p', 'text': material.text});
          planned.first['blocks'] = blocks;
        }
        final plan = TranslationPlan(planned);
        if (plan.chunks.length > 8 ||
            utf8.encode(jsonEncode(data)).length > 200000) {
          throw ApiFailure(413, '详细介绍较长，内置免费预算无法完整翻译。请选择自定义AI，原文不会被截断');
        }
      }
      previous = data;
      draft = null;
    }
    final data = previous;
    if (data == null) throw ApiFailure(400, '还没有可恢复的任务');
    if (keepOriginal) {
      final originals = rows(jsonDecode(jsonEncode(data['sources'])));
      if (text(data['material']).trim().isNotEmpty) {
        final blocks = rows(originals.first['blocks']);
        blocks.add({'kind': 'p', 'text': text(data['material'])});
        originals.first['blocks'] = blocks;
      }
      final plan = TranslationPlan(originals), values = <String, String>{};
      for (final chunk in plan.chunks) {
        for (final v in chunk) {
          values[text(v['id'])] = text(v['text']);
        }
      }
      final original = AiDraft.parse(
        plan.assemble(originals, type, values),
        originals,
        service: true,
      );
      if (current && run == job) {
        setState(() {
          draft = original;
          status = '已按原文带入，没有调用AI，也没有消耗内置次数';
        });
      }
      return;
    }

    if (custom) {
      final result = await io.custom(
        address.text,
        keyInput.text,
        model.text,
        data,
      );
      if (current && run == job) {
        setState(() {
          draft = result;
          status = '已逐段翻译，介绍图片保留原顺序；请核对原文后导入';
        });
      }
    } else {
      await verify();
      if (!current || run != job) return;
      final result = await io.json(
        Uri.parse('$serviceOrigin/ai/v2/draft'),
        body: data,
        token: widget.app.token,
        builtin: true,
        timeout: const Duration(seconds: 240),
      );
      final d = AiDraft.parse(result['draft'], sources, service: true);
      if (current && run == job) {
        setState(() {
          draft = d;
          status =
              '今日个人剩余 ${result['remaining']} 次 · 共享翻译预算剩余 ${result['shared_remaining']} 段，UTC零点重置';
        });
      }
    }
  }

  Future<void> extract({bool manual = false}) async {
    final job = run, io = transport;
    final urls = links.text
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (urls.isEmpty || urls.length > 3) {
      throw ApiFailure(400, '请输入1至3个HTTPS作品链接，每行一个');
    }
    final found = <Json>[];
    for (final u in urls) {
      aiSourceUrl(u);
      found.add(
        manual ? {'url': u, 'text': '', 'cover': ''} : await io.source(u),
      );
    }
    if (current && run == job) {
      setState(() {
        sources = found;
        draft = null;
        previous = null;
        status = manual
            ? '已采用链接及手动素材，粘贴作品介绍后生成'
            : '已提取完整介绍：${found.fold<int>(0, (n, s) => n + text(s['text']).length)}字 / ${found.fold<int>(0, (n, s) => n + rows(s['blocks']).where((b) => b['kind'] == 'image').length)}张图片，原文不会精简';
      });
    }
  }

  @override
  void dispose() {
    run++;
    transport.close();
    for (final c in [links, material, address, keyInput, model]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Row(
      children: [
        Icon(Icons.auto_awesome_outlined, color: violet),
        SizedBox(width: 10),
        Text('AI 投稿助手'),
      ],
    ),
    content: SizedBox(
      width: 820,
      child: !loaded
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('内置 AI')),
                      ButtonSegment(value: true, label: Text('自定义 AI')),
                    ],
                    selected: {custom},
                    onSelectionChanged: busy
                        ? null
                        : (v) async {
                            setState(() {
                              custom = v.first;
                              draft = null;
                              previous = null;
                            });
                            try {
                              await save(validate: false);
                            } catch (_) {
                              if (current) setState(() => status = "无法保存加密配置");
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    custom
                        ? '直连你填写的服务，逐段忠实翻译，不改写；图片原样带入。密钥由Windows DPAPI加密保存，不占内置额度，仍受服务商与设备容量限制。'
                        : '只翻译原文，不概括或补写；段落与介绍图片按原顺序保留。内置每UID每天3次，全体共享16段翻译预算；长介绍分段处理，超出预算提示切换自定义AI，不截断内容。',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (custom) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: address,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        labelText: 'HTTPS API地址',
                        hintText: 'https://你的服务/v1',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: keyInput,
                      enabled: !busy,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'API Key（可留空，按服务要求）',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: model,
                      enabled: !busy,
                      decoration: const InputDecoration(labelText: '模型名称'),
                    ),
                    Wrap(
                      spacing: 10,
                      children: [
                        TextButton.icon(
                          onPressed: busy
                              ? null
                              : () => action(() async {
                                  await save();
                                  setState(() => status = '配置已加密保存');
                                }),
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('保存配置'),
                        ),
                        TextButton.icon(
                          onPressed: busy
                              ? null
                              : () => action(() async {
                                  await save();
                                  await transport.json(
                                    aiEndpoint(address.text),
                                    token: keyInput.text.trim(),
                                    body: {
                                      'model': model.text.trim(),
                                      'messages': [
                                        {'role': 'user', 'content': 'Reply OK'},
                                      ],
                                      'stream': false,
                                      'max_tokens': 8,
                                    },
                                  );
                                  if (current) {
                                    setState(
                                      () => status = '连接成功（测试可能消耗服务商额度）',
                                    );
                                  }
                                }),
                          icon: const Icon(Icons.network_check),
                          label: const Text('测试连接'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text('原文逐段翻译 · 不概括，不补写，图片保持原样'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: links,
                    enabled: !busy,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '作品链接（每行一个，最多3个）',
                      hintText: 'Steam / DLsite / 官网 / 其他公开介绍页',
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: busy ? null : () => action(() => extract()),
                        icon: const Icon(Icons.travel_explore),
                        label: const Text('提取链接'),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => action(() => extract(manual: true)),
                        child: const Text('使用粘贴素材'),
                      ),
                    ],
                  ),
                  for (var i = 0; i < sources.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextFormField(
                        key: ValueKey(
                          '${sources[i]['url']}-${sources[i]['text'].hashCode}',
                        ),
                        initialValue: text(sources[i]['text']),
                        readOnly: rows(sources[i]['blocks']).isNotEmpty,
                        enabled: !busy,
                        minLines: 2,
                        maxLines: 5,
                        decoration: InputDecoration(
                          labelText:
                              '来源 ${i + 1} · 完整介绍 / ${rows(sources[i]['blocks']).where((b) => b['kind'] == 'image').length}张图片',
                          helperText: text(sources[i]['url']),
                          helperMaxLines: 1,
                        ),
                        onChanged: (s) {
                          sources[i]['text'] = s;
                        },
                      ),
                    ),
                  CheckboxListTile(
                    value: keepOriginal,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => keepOriginal = v!),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('原文已是中文：跳过AI，原样带入'),
                    subtitle: const Text('文字和图片保持原样，不消耗AI次数'),
                  ),
                  TextField(
                    controller: material,
                    enabled: !busy,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: '补充作品素材（可选）',
                      hintText: '网页无法提取时粘贴公开介绍。不要填写密码、会话或私人资料。',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (busy) const LinearProgressIndicator(),
                  if (status.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        status,
                        style: const TextStyle(fontSize: 12, color: violet),
                      ),
                    ),
                  if (draft != null) ...[
                    const Divider(),
                    Text(
                      draft!.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (draft!.data['blocks'] is List)
                      HtmlWidget(
                        draft!.body,
                        textStyle: const TextStyle(fontSize: 13),
                        customWidgetBuilder: (element) {
                          if (element.localName == 'img') {
                            return Image.network(
                              element.attributes['src'] ?? '',
                              fit: BoxFit.contain,
                              errorBuilder: (c, e, st) =>
                                  const Text('[原文图片暂时无法加载，链接仍会保留]'),
                            );
                          }
                          return null;
                        },
                      )
                    else
                      SelectableText(text(draft!.data['summary'])),
                    const Text(
                      'AI仅翻译文字，图片不翻译；请核对译文。导入只修改本机草稿，图片以原始HTTPS链接插入，不会自动发表。',
                      style: TextStyle(fontSize: 12),
                    ),
                    Wrap(
                      children: [
                        for (final entry in [
                          ('标题', importTitle, 0),
                          ('正文', importBody, 1),
                          ('封面URL', importCover, 3),
                          ('正文追加', append, 4),
                        ])
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: entry.$2,
                                onChanged: busy
                                    ? null
                                    : (v) => setState(() {
                                        switch (entry.$3) {
                                          case 0:
                                            importTitle = v!;
                                          case 1:
                                            importBody = v!;
                                          case 2:
                                            importTags = v!;
                                          case 3:
                                            importCover = v!;
                                          case 4:
                                            append = v!;
                                        }
                                      }),
                              ),
                              Text(entry.$1),
                            ],
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          transport.close();
          Navigator.pop(context);
        },
        child: const Text('关闭'),
      ),
      if (busy) TextButton(onPressed: cancel, child: const Text('取消任务')),
      if (!busy && previous != null && !custom && !keepOriginal)
        TextButton(
          onPressed: () => action(() => generate(recover: true)),
          child: const Text('恢复上次结果'),
        ),
      FilledButton.tonal(
        onPressed: busy || !loaded ? null : () => action(() => generate()),
        child: const Text('翻译并生成草稿'),
      ),
      if (draft != null)
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  if (!current) return;
                  if ((!append || importTitle || importTags || importCover) &&
                      !await confirm(
                        context,
                        '导入AI草稿？',
                        '选中的字段将替换当前内容。正文可选择追加，导入后可撤销正文。',
                        action: '导入',
                      )) {
                    return;
                  }
                  if (context.mounted && current) {
                    Navigator.pop(
                      context,
                      AiImport(
                        draft!,
                        importTitle,
                        importBody,
                        importTags,
                        importCover,
                        append,
                      ),
                    );
                  }
                },
          child: const Text('导入选中字段'),
        ),
    ],
  );
}
