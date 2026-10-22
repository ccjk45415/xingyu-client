import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/ai.dart';
import '../core/translation.dart';
import '../core/submission_guidance.dart';
import '../core/submission_extras.dart';
import '../core/media.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../core/api.dart';
import '../core/state.dart';
import '../ui/shared.dart';
import '../ui/ai_panels.dart';

class AiImport {
  final AiDraft draft;
  final bool title, body, tags, cover, append;
  final Set<int>? categories;
  final String kind;
  final bool aiImages;
  final String? suggestedTitle;
  final String? purchaseProof;
  AiImport(
    this.draft,
    this.title,
    this.body,
    this.tags,
    this.cover,
    this.append, {
    this.categories,
    this.kind = 'other',
    this.aiImages = false,
    this.suggestedTitle,
    this.purchaseProof,
  });
}

Future<AiImport?> showAiAssistant(
  BuildContext context, {
  Future<Uint8List?> Function(BuildContext)? proofPicker,
}) {
  final app = stateOf(context);
  return showDialog<AiImport>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AiAssistantDialog(app, proofPicker: proofPicker),
  );
}

class AiAssistantDialog extends StatefulWidget {
  final AppState app;
  final Future<Uint8List?> Function(BuildContext)? proofPicker;
  const AiAssistantDialog(this.app, {super.key, this.proofPicker});
  @override
  State<AiAssistantDialog> createState() => _AiAssistantDialogState();
}

class _AiAssistantDialogState extends State<AiAssistantDialog> {
  final links = TextEditingController(),
      material = TextEditingController(),
      address = TextEditingController(),
      keyInput = TextEditingController(),
      model = TextEditingController(),
      guideAuthor = TextEditingController(),
      guideDate = TextEditingController(),
      guideAttributes = TextEditingController(),
      draftTitle = TextEditingController();
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
  String type = 'auto', status = '', guideKind = 'other', guidePath = '';
  SubmissionGuidance? guidance;
  bool guideChosen = false, guideAiImages = false, importCategories = false;
  bool selfPurchased = false, proofUploading = false;
  String proofUrl = '';
  bool get disabled => busy || proofUploading;
  int run = 0, sourceRevision = 0;
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
      guidance = await SubmissionGuidance.load();
      if (widget.app.categories.isEmpty) {
        try {
          await widget.app.loadCategories();
        } catch (_) {
          /* Advice stays available offline. */
        }
      }
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
    if (disabled || !current) return;
    final id = ++run;
    setState(() {
      busy = true;
      status = '正在处理，请稍候。原标题将保持不变。';
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
      final data = translationRequest(
        sources,
        material.text,
        guidance?.transportType(guideKind) ?? type,
        nonce(),
      );
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
          draftTitle.text = defaultTitle;
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
          draftTitle.text = defaultTitle;
          status = '已逐段翻译，介绍图片保留原顺序；请核对原文后导入';
        });
      }
    } else {
      await verify();
      if (!current || run != job) return;
      final result = await io.json(
        Uri.parse('$serviceOrigin/ai/v2/draft'),
        body: builtinBodyOnlyRequest(data),
        token: widget.app.token,
        builtin: true,
        timeout: const Duration(seconds: 240),
      );
      final d = AiDraft.parse(
        restoreOriginalSourceTitles(result['draft'], data),
        sources,
        service: true,
      );
      if (current && run == job) {
        setState(() {
          draft = d;
          draftTitle.text = defaultTitle;
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
        if (sources.isNotEmpty) proofUrl = '';
        sourceRevision++;
        sources = found;
        if (!guideChosen && guidance != null) {
          guideKind = guidance!.guess(found);
          guidePath = availablePaths.length == 1 ? availablePaths.single : '';
        }
        draft = null;
        previous = null;
        status = manual
            ? '已采用链接及手动素材，粘贴作品介绍后生成'
            : '已提取完整介绍：${found.fold<int>(0, (n, s) => n + text(s['text']).length)}字 / ${found.fold<int>(0, (n, s) => n + rows(s['blocks']).where((b) => b['kind'] == 'image').length)}张图片，原文不会精简';
      });
    }
  }

  List<String> get availablePaths =>
      guidance
          ?.paths(guideKind)
          .where((p) => guidance!.resolve(widget.app.categories, p).isNotEmpty)
          .toList() ??
      [];
  Set<int> get proposedCategories =>
      guidance?.resolve(widget.app.categories, guidePath) ?? {};
  Future<void> showGuideReport() async {
    final guide = guidance, currentDraft = draft;
    if (guide == null || currentDraft == null) return;
    final report = guide.report(
      guide.check(
        title: draftTitle.text,
        body: previewBody,
        selected: proposedCategories,
        tree: widget.app.categories,
        kind: guideKind,
        aiImages: guideAiImages,
      ),
    );
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('官网规范辅助检查'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(child: SelectableText(report)),
        ),
        actions: [
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse(guide.sourceUrl),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('官网完整规则'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('返回编辑'),
          ),
        ],
      ),
    );
  }

  String get defaultTitle => withDlsiteIds(
    draft?.title ?? '',
    rows(draft?.data['sources']).map((s) => text(s['url'])),
  );
  String get previewBody => selfPurchased && proofUrl.isNotEmpty
      ? placePurchaseProof(draft!.body, proofUrl)
      : draft!.body;

  Future<void> uploadProof() async {
    if (!current || disabled || !selfPurchased) return;
    setState(() {
      proofUploading = true;
      status = '选择自购证明图片，仅上传官网图床';
    });
    try {
      final bytes = await (widget.proofPicker ?? pickJpeg)(context);
      if (bytes == null || !current) return;
      setState(() => status = '正在上传官网图床…');
      final result = await widget.app.site.upload(
        'upload/image',
        'image',
        bytes,
      );
      if (!current) return;
      final data = object(result['data']);
      var url = text(
        data['url'],
        text(data['link'], text(result['url'], text(result['link']))),
      );
      if (url.startsWith('//')) {
        url = 'https:$url';
      } else if (url.startsWith('/')) {
        url = '$siteOrigin$url';
      }
      if (!url.startsWith('https://') || !safeExternal(url)) {
        throw ApiFailure(400, '官网没有返回有效的图片地址，请重新上传');
      }
      setState(() {
        proofUrl = url;
        status = '自购证明已上传官网图床，导入时会放在下载模块之前';
      });
    } catch (e) {
      if (current) {
        setState(() => status = e is ApiFailure ? e.message : '证明上传失败，请重试');
      }
    } finally {
      if (mounted) setState(() => proofUploading = false);
    }
  }

  Widget purchaseForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CheckboxListTile(
        key: const Key('ai.selfPurchased'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: selfPurchased,
        onChanged: disabled ? null : (v) => setState(() => selfPurchased = v!),
        title: const Text(
          '自购资源',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: const Text(
          '仅本人购买时勾选；非自购不需要证明',
          style: TextStyle(fontSize: 12),
        ),
      ),
      if (selfPurchased) ...[
        const AiNotice(
          '请上传一张自购证明，先遮盖邮箱、订单号等私人信息。图片上传官网图床，导入后会随正文公开，不会交给 AI。',
          icon: Icons.receipt_long_outlined,
        ),
        const SizedBox(height: 10),
        if (proofUrl.isNotEmpty) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: Image.network(
              proofUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const AiNotice('证明已上传，图片暂未加载', icon: Icons.image_outlined),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: disabled ? null : uploadProof,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: Text(proofUrl.isEmpty ? '上传自购证明' : '更换证明图片'),
            ),
            if (proofUrl.isNotEmpty)
              TextButton.icon(
                onPressed: disabled
                    ? null
                    : () => setState(() => proofUrl = ''),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('移除证明'),
              ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    ],
  );

  Widget guideForm() {
    final guide = guidance;
    if (guide == null) return const Text('规范模块暂不可用，请对照官网须知核对。');
    return ExpansionTile(
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      tilePadding: EdgeInsets.zero,
      title: const Text('官网规范 · 标题与分类辅助'),
      subtitle: Text('展开确认分类与已知信息 · 不消耗AI次数'),
      children: [
        const SizedBox(height: 16),
        Text(
          '作品类型',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: guideKind,
          key: ValueKey('guide.kind.$guideKind'),
          isExpanded: true,
          decoration: aiInput(null, icon: Icons.category_outlined),
          items: guide.profiles
              .map(
                (p) => DropdownMenuItem(
                  value: text(p['id']),
                  child: Text(text(p['label'])),
                ),
              )
              .toList(),
          onChanged: disabled
              ? null
              : (v) => setState(() {
                  guideChosen = true;
                  guideKind = v!;
                  guidePath = availablePaths.length == 1
                      ? availablePaths.single
                      : '';
                  importCategories = false;
                }),
        ),
        const SizedBox(height: 14),
        Text(
          '投稿分类',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('guide.path.$guideKind.$guidePath'),
          initialValue: guidePath,
          isExpanded: true,
          decoration: aiInput(null, icon: Icons.account_tree_outlined),
          items: [
            const DropdownMenuItem(value: '', child: Text('请选择实际子分类，不推断汉化或版本')),
            ...availablePaths.map(
              (p) => DropdownMenuItem(value: p, child: Text(p)),
            ),
          ],
          onChanged: disabled ? null : (v) => setState(() => guidePath = v!),
        ),
        if (availablePaths.isEmpty)
          const Text(
            '当前目录未匹配到建议分类；仍可翻译，导入时保留原分类并手动选择。',
            style: TextStyle(fontSize: 12),
          ),
        for (final tip in guide.profile(guideKind)['tips'] as List)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('• $tip', style: const TextStyle(fontSize: 12)),
          ),
        TextField(
          controller: guideAuthor,
          enabled: !disabled,
          maxLength: 200,
          decoration: aiInput(
            '作者 / 开发商 / 社团',
            helper: '仅填写来源中已确认的信息',
            icon: Icons.person_outline_rounded,
          ),
        ),
        TextField(
          controller: guideDate,
          enabled: !disabled,
          maxLength: 40,
          decoration: aiInput(
            '发行日期',
            helper: '未知可留空；不是上传日期',
            icon: Icons.event_outlined,
          ),
        ),
        TextField(
          controller: guideAttributes,
          enabled: !disabled,
          maxLength: 500,
          decoration: aiInput(
            '版本、平台与格式',
            helper: '多个属性用逗号分隔',
            icon: Icons.sell_outlined,
          ),
        ),
        purchaseForm(),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: guideAiImages,
          onChanged: disabled
              ? null
              : (v) => setState(() {
                  guideAiImages = v!;
                  if (v) {
                    guideChosen = true;
                    guideKind = 'pictures';
                    guidePath = availablePaths.contains('图片 / 图包')
                        ? '图片 / 图包'
                        : '';
                  }
                }),
          title: const Text('资源为 AI 生成图片', style: TextStyle(fontSize: 13)),
          subtitle: const Text(
            '仅限资源本身；使用AI写稿不需要勾选',
            style: TextStyle(fontSize: 12),
          ),
        ),
        TextButton.icon(
          onPressed: () => launchUrl(
            Uri.parse(guide.sourceUrl),
            mode: LaunchMode.externalApplication,
          ),
          icon: const Icon(Icons.open_in_new),
          label: const Text('官网投稿须知'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    run++;
    transport.close();
    for (final c in [
      links,
      material,
      address,
      keyInput,
      model,
      guideAuthor,
      guideDate,
      guideAttributes,
      draftTitle,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget servicePanel() => AiPanel(
    title: 'AI 服务',
    subtitle: '原标题保留，只翻译正文',
    icon: Icons.auto_awesome_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              icon: Icon(Icons.cloud_outlined),
              label: Text('内置 AI'),
            ),
            ButtonSegment(
              value: true,
              icon: Icon(Icons.key_rounded),
              label: Text('自定义 AI'),
            ),
          ],
          selected: {custom},
          onSelectionChanged: disabled
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
                    if (current) setState(() => status = '配置暂未保存，请重试');
                  }
                },
        ),
        const SizedBox(height: 12),
        AiNotice(
          custom ? '连接你自己的模型服务。密钥仅在本机加密保存。' : '认证仓库账号后使用共享免费额度，无需填写 API。',
          icon: Icons.shield_outlined,
        ),
        if (custom) ...[
          const SizedBox(height: 14),
          TextField(
            controller: address,
            enabled: !disabled,
            decoration: aiInput(
              'API 地址',
              hint: 'https://你的服务/v1',
              icon: Icons.dns_outlined,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: keyInput,
            enabled: !disabled,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: aiInput(
              'API Key',
              helper: '服务无需密钥时可留空',
              icon: Icons.key_rounded,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: model,
            enabled: !disabled,
            decoration: aiInput('模型名称', icon: Icons.memory_rounded),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: disabled
                    ? null
                    : () => action(() async {
                        await save();
                        setState(() => status = '配置已加密保存在本机');
                      }),
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('保存配置'),
              ),
              TextButton.icon(
                onPressed: disabled
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
                          setState(() => status = '连接成功；测试可能消耗服务商额度');
                        }
                      }),
                icon: const Icon(Icons.network_check_rounded, size: 18),
                label: const Text('测试连接'),
              ),
            ],
          ),
        ],
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          title: const Text('额度与隐私说明', style: TextStyle(fontSize: 12)),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                custom
                    ? '不占内置次数，仍受服务商额度和设备容量限制。公开介绍会发送至你填写的 API 服务；测试连接也可能计费。'
                    : '每 UID 每天 3 次，全体共享 16 段翻译预算，UTC 零点重置。生成开始即计次，失败不自动重试。介绍过长会提示切换自定义 AI，不截断内容。所选介绍交给 Cloudflare AI，结果缓存 1 小时。',
                style: const TextStyle(fontSize: 12, height: 1.6),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget sourcePanel() => AiPanel(
    title: '添加来源',
    subtitle: '支持 Steam、DLsite、游戏官网及其他公开介绍页',
    icon: Icons.link_rounded,
    step: '01',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: links,
          enabled: !disabled,
          minLines: 2,
          maxLines: 3,
          decoration: aiInput(
            '作品链接',
            hint: '粘贴 HTTPS 链接，每行一个',
            helper: '最多 3 个来源；优先提取详细介绍和原图',
            icon: Icons.link_rounded,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            FilledButton.tonalIcon(
              onPressed: disabled ? null : () => action(() => extract()),
              icon: const Icon(Icons.travel_explore_rounded, size: 18),
              label: const Text('提取介绍'),
            ),
            OutlinedButton.icon(
              onPressed: disabled
                  ? null
                  : () => action(() => extract(manual: true)),
              icon: const Icon(Icons.content_paste_rounded, size: 18),
              label: const Text('手动粘贴'),
            ),
          ],
        ),
        for (var i = 0; i < sources.length; i++) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.article_outlined, size: 18, color: violet),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '来源 ${i + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${rows(sources[i]['blocks']).where((b) => b['kind'] == 'image').length} 张图片',
                style: const TextStyle(fontSize: 12, color: violet),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey(
              'ai.source.$i.title.${sources[i]['url']}.$sourceRevision',
            ),
            initialValue: text(sources[i]['title']),
            enabled: !disabled,
            decoration: aiInput(
              '原标题',
              helper: '保持原语言；提取缺失时请手动填写',
              icon: Icons.title_rounded,
            ),
            onChanged: (v) => sources[i]['title'] = v,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey(
              'ai.source.$i.body.${sources[i]['url']}.$sourceRevision',
            ),
            initialValue: text(sources[i]['text']),
            readOnly: rows(sources[i]['blocks']).isNotEmpty,
            enabled: !disabled,
            minLines: 3,
            maxLines: 6,
            decoration: aiInput(
              '公开介绍',
              helper: rows(sources[i]['blocks']).isEmpty
                  ? '粘贴原文，正文会逐段翻译'
                  : '已保留完整原文与图片顺序；此处供核对',
            ),
            onChanged: (v) => sources[i]['text'] = v,
          ),
          const SizedBox(height: 6),
          SelectableText(
            text(sources[i]['url']),
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        CheckboxListTile(
          value: keepOriginal,
          onChanged: disabled ? null : (v) => setState(() => keepOriginal = v!),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            '正文无需翻译',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            '原文已是中文时直接带入，不消耗 AI 次数',
            style: TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: material,
          enabled: !disabled,
          minLines: 2,
          maxLines: 5,
          decoration: aiInput(
            '补充素材（可选）',
            hint: '提取失败时可在此粘贴公开介绍',
            helper: '不要填写密码、会话或私人资料',
            icon: Icons.note_add_outlined,
          ),
        ),
      ],
    ),
  );

  Widget previewPanel() => AiPanel(
    title: '确认草稿',
    subtitle: '先检查效果，再决定导入哪些字段',
    icon: Icons.preview_outlined,
    step: '03',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AiNotice(
          '原标题原样保留；正文忠实翻译，图片保持原样。导入只修改本机草稿。',
          icon: Icons.translate_rounded,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: draftTitle,
          enabled: !disabled,
          minLines: 1,
          maxLines: 3,
          decoration: aiInput(
            '投稿标题',
            helper: draft!.title.isEmpty
                ? '未提取到原标题，请先补充作品名称'
                : '保留原标题；DLsite 链接自动追加 [RJ号]',
            icon: Icons.title_rounded,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton.icon(
              onPressed: disabled
                  ? null
                  : () => setState(
                      () => draftTitle.text =
                          guidance?.title(
                            guideKind,
                            defaultTitle,
                            author: guideAuthor.text,
                            date: guideDate.text,
                            attributes: guideAttributes.text,
                            aiImages: guideAiImages,
                          ) ??
                          defaultTitle,
                    ),
              icon: const Icon(Icons.auto_fix_high_outlined, size: 18),
              label: const Text('套用投稿格式'),
            ),
            TextButton.icon(
              onPressed: disabled ? null : showGuideReport,
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('检查官网规范'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          key: const Key('ai.draft.preview'),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: violet.withValues(alpha: .035),
            border: Border.all(color: violet.withValues(alpha: .10)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: draft!.data['blocks'] is List
              ? HtmlWidget(
                  previewBody,
                  textStyle: const TextStyle(fontSize: 14, height: 1.7),
                  customWidgetBuilder: (element) => element.localName == 'img'
                      ? ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 320),
                          child: Image.network(
                            element.attributes['src'] ?? '',
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const AiNotice(
                              '图片暂未加载，导入时仍会保留原图链接',
                              icon: Icons.image_outlined,
                            ),
                          ),
                        )
                      : null,
                )
              : SelectableText(text(draft!.data['summary'])),
        ),
        const SizedBox(height: 16),
        const Text(
          '导入选项',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final entry in [
              ('替换标题', importTitle, 0),
              ('导入正文', importBody, 1),
              ('使用来源封面', importCover, 3),
              ('追加到正文', append, 4),
            ])
              FilterChip(
                label: Text(entry.$1),
                selected: entry.$2,
                onSelected: disabled
                    ? null
                    : (v) => setState(() {
                        switch (entry.$3) {
                          case 0:
                            importTitle = v;
                          case 1:
                            importBody = v;
                          case 3:
                            importCover = v;
                          case 4:
                            append = v;
                        }
                      }),
              ),
          ],
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: importCategories,
          onChanged: disabled || proposedCategories.isEmpty
              ? null
              : (v) => setState(() => importCategories = v!),
          title: const Text('使用已确认分类', style: TextStyle(fontSize: 13)),
          subtitle: Text(
            guidePath.isEmpty ? '未确认分类，保留原选择' : '$guidePath（含上级分类；将替换原选择）',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    ),
  );

  Future<void> importDraft() async {
    if (!current || disabled || draft == null) return;
    if (selfPurchased && (proofUrl.isEmpty || !importBody)) {
      setState(
        () => status = proofUrl.isEmpty
            ? '自购资源请先上传一张自购证明'
            : '自购证明需随正文导入，请勾选“导入正文”',
      );
      return;
    }
    if (importTitle) {
      draftTitle.text = withDlsiteIds(
        draftTitle.text,
        rows(draft!.data['sources']).map((s) => text(s['url'])),
      );
    }
    if (importTitle && draftTitle.text.trim().isEmpty) {
      setState(() => status = '请补充投稿标题');
      return;
    }
    if (importCategories && proposedCategories.isEmpty) {
      setState(() => status = '请重新确认分类');
      return;
    }
    if ((!append ||
            importTitle ||
            importTags ||
            importCover ||
            importCategories) &&
        !await confirm(
          context,
          '导入这份草稿？',
          '选中的标题、分类或封面将替换原字段。正文按你的选择追加或替换，尚未提交网站。',
          action: '导入',
        )) {
      return;
    }
    if (!mounted || !current) return;
    Navigator.pop(
      context,
      AiImport(
        draft!,
        importTitle,
        importBody,
        importTags,
        importCover,
        append,
        categories: importCategories ? {...proposedCategories} : null,
        kind: guideKind,
        aiImages: guideAiImages,
        suggestedTitle: draftTitle.text.trim(),
        purchaseProof: selfPurchased ? proofUrl : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 640;
    return Dialog(
      insetPadding: EdgeInsets.all(compact ? 12 : 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: Color.alphaBlend(
        violet.withValues(alpha: .035),
        colors.surface,
      ),
      child: SizedBox(
        width: 1120,
        height: MediaQuery.sizeOf(context).height * .92,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(compact ? 18 : 26, 20, 14, 16),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [violet, Color(0xffb39be9)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 25,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI 投稿助手',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          '保留原标题，把介绍整理成投稿草稿',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭助手',
                    onPressed: () {
                      transport.close();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: !loaded
                  ? const Center(child: CircularProgressIndicator())
                  : Scrollbar(
                      child: SingleChildScrollView(
                        key: const Key('ai.panel.scroll'),
                        padding: EdgeInsets.fromLTRB(
                          compact ? 12 : 24,
                          0,
                          compact ? 12 : 24,
                          22,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            LayoutBuilder(
                              builder: (context, size) {
                                final details = Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    AiPanel(
                                      title: '投稿资料',
                                      subtitle: '可选填写，未知信息保持留空',
                                      icon: Icons.tune_rounded,
                                      step: '02',
                                      child: guideForm(),
                                    ),
                                    const SizedBox(height: 16),
                                    const AiNotice(
                                      '原标题不翻译。需要官网标题格式时，在草稿中手动点击“套用投稿格式”。',
                                      icon: Icons.title_rounded,
                                    ),
                                  ],
                                );
                                return size.maxWidth >= 840
                                    ? Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            flex: 6,
                                            child: sourcePanel(),
                                          ),
                                          const SizedBox(width: 18),
                                          Expanded(
                                            flex: 5,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                servicePanel(),
                                                const SizedBox(height: 16),
                                                details,
                                              ],
                                            ),
                                          ),
                                        ],
                                      )
                                    : Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          sourcePanel(),
                                          const SizedBox(height: 16),
                                          servicePanel(),
                                          const SizedBox(height: 16),
                                          details,
                                        ],
                                      );
                              },
                            ),
                            if (status.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Semantics(
                                  liveRegion: true,
                                  child: AiNotice(
                                    status,
                                    icon: busy
                                        ? Icons.hourglass_top_rounded
                                        : Icons.info_outline_rounded,
                                  ),
                                ),
                              ),
                            if (draft != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: previewPanel(),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
            if (disabled) const LinearProgressIndicator(minHeight: 2),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 16 : 24,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(
                  top: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: .4),
                  ),
                ),
              ),
              child: Row(
                children: [
                  if (!compact)
                    Expanded(
                      child: Text(
                        disabled ? '正在处理，原标题保持不变…' : '生成后先预览，导入后仍可编辑',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        if (busy)
                          OutlinedButton.icon(
                            onPressed: cancel,
                            icon: const Icon(
                              Icons.stop_circle_outlined,
                              size: 18,
                            ),
                            label: const Text('取消任务'),
                          ),
                        if (!disabled &&
                            previous != null &&
                            !custom &&
                            !keepOriginal)
                          TextButton.icon(
                            onPressed: () =>
                                action(() => generate(recover: true)),
                            icon: const Icon(Icons.restore_rounded, size: 18),
                            label: const Text('恢复结果'),
                          ),
                        FilledButton.tonalIcon(
                          onPressed: disabled || !loaded
                              ? null
                              : () => action(() => generate()),
                          icon: const Icon(Icons.translate_rounded, size: 18),
                          label: Text(draft == null ? '生成草稿' : '重新生成'),
                        ),
                        if (draft != null)
                          FilledButton.icon(
                            onPressed: disabled ? null : importDraft,
                            icon: const Icon(
                              Icons.file_download_outlined,
                              size: 18,
                            ),
                            label: const Text('导入草稿'),
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
    );
  }
}
