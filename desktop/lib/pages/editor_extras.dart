import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html;
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/editor_extra_rules.dart';

/// Native editor dialogs. Null cancels; empty image result removes the atom.
Future<String?> showEditorExtra(
  BuildContext context,
  String tool, {
  String selectedHtml = '',
  required SiteApi api,
  Json? account,
  Future<String?> Function()? uploadImage,
}) async {
  final selection = selectedHtml.isEmpty ? '文字' : selectedHtml;
  switch (tool) {
    case 'fontFamily':
      final index = await _choice(context, '字体', extraFontNames);
      return index == null ? null : extraFont(index, selection);
    case 'lineHeight':
      const choices = ['1', '1.15', '1.5', '1.75', '2', '2.5', '3'];
      final index = await _choice(context, '段落行高', choices);
      return index == null ? null : extraLineHeight(choices[index], selection);
    case 'rainbow':
      return extraInline('text-rainbow', selection);
    case 'blackbar':
      return extraInline('text-forbidden', selection);
    case 'emoji':
      return _symbols(context, '表情', extraEmoji);
    case 'special':
      return _symbols(context, '特殊字符', extraSpecial);
    case 'collapse':
      return showDialog<String>(
        context: context,
        builder: (_) =>
            _CollapseDialog(html.parseFragment(selectedHtml).text ?? ''),
      );
    case 'randomFileName':
      return showDialog<String>(
        context: context,
        builder: (_) => const _RandomNameDialog(),
      );
    case 'table':
      return showDialog<String>(
        context: context,
        builder: (_) => _TableDialog(selectedHtml),
      );
    case 'poll':
      return showDialog<String>(
        context: context,
        builder: (_) => _ReferenceDialog(
          api: api,
          account: account,
          uploadImage: uploadImage,
        ),
      );
    case 'lottery':
      if (!extraLotteryAllowed(account)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('抽奖插入仅对官网管理员和编辑开放')));
        return null;
      }
      return showDialog<String>(
        context: context,
        builder: (_) =>
            _ReferenceDialog(api: api, account: account, lottery: true),
      );
    default:
      return null;
  }
}

Future<int?> _choice(BuildContext context, String title, List<String> values) =>
    showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < values.length; i++)
                  ListTile(
                    title: Text(values[i]),
                    onTap: () => Navigator.pop(context, i),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
Future<String?> _symbols(
  BuildContext context,
  String title,
  List<String> values,
) => showDialog<String>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in values)
              Tooltip(
                message: '插入 $value',
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, extraEscape(value)),
                  child: Text(value, style: const TextStyle(fontSize: 20)),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
    ],
  ),
);
Widget _input(
  TextEditingController controller,
  String label, {
  int lines = 1,
  Widget? suffix,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 14),
  child: TextField(
    controller: controller,
    minLines: lines,
    maxLines: lines > 1 ? 8 : 1,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      suffixIcon: suffix,
    ),
  ),
);
Widget _error(String? error) => error == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(error, style: const TextStyle(color: Colors.red)),
      );

class _CollapseDialog extends StatefulWidget {
  final String initial;
  const _CollapseDialog(this.initial);
  @override
  State<_CollapseDialog> createState() => _CollapseState();
}

class _CollapseState extends State<_CollapseDialog> {
  final title = TextEditingController();
  late final body = TextEditingController(text: widget.initial);
  bool expanded = false;
  String? error;
  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('插入折叠内容'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _input(title, '折叠标题'),
            _input(body, '折叠内容', lines: 5),
            SwitchListTile(
              value: expanded,
              onChanged: (v) => setState(() => expanded = v),
              title: const Text('默认展开'),
            ),
            _error(error),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          try {
            Navigator.pop(
              context,
              extraCollapse(title.text, body.text, expanded),
            );
          } catch (e) {
            setState(() => error = e.toString());
          }
        },
        child: const Text('插入'),
      ),
    ],
  );
}

class _RandomNameDialog extends StatefulWidget {
  const _RandomNameDialog();
  @override
  State<_RandomNameDialog> createState() => _RandomNameState();
}

class _RandomNameState extends State<_RandomNameDialog> {
  late final name = TextEditingController(text: extraRandomName());
  bool copied = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('随机文件名'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: '文件名',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  name.text = extraRandomName();
                  copied = false;
                }),
                icon: const Icon(Icons.refresh),
                label: const Text('重新生成'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: name.text));
                  if (mounted) setState(() => copied = true);
                },
                icon: Icon(copied ? Icons.check : Icons.copy),
                label: Text(copied ? '已复制' : '复制文件名'),
              ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, extraEscape(name.text)),
        child: const Text('插入'),
      ),
    ],
  );
}

Future<String?> editEditorImage(
  BuildContext context,
  String originalHtml, {
  Future<String?> Function()? uploadImage,
}) => showDialog<String>(
  context: context,
  builder: (_) => _ImageDialog(originalHtml, uploadImage),
);

class _ImageDialog extends StatefulWidget {
  final String original;
  final Future<String?> Function()? uploadImage;
  const _ImageDialog(this.original, this.uploadImage);
  @override
  State<_ImageDialog> createState() => _ImageState();
}

class _ImageState extends State<_ImageDialog> {
  late final image = html.parseFragment(widget.original).querySelector('img');
  late final src = TextEditingController(text: image?.attributes['src']),
      alt = TextEditingController(text: image?.attributes['alt']),
      width = TextEditingController(
        text: extraStyleValue(text(image?.attributes['style']), 'width').isEmpty
            ? image?.attributes['width']
            : extraStyleValue(text(image?.attributes['style']), 'width'),
      ),
      height = TextEditingController(
        text:
            extraStyleValue(text(image?.attributes['style']), 'height').isEmpty
            ? image?.attributes['height']
            : extraStyleValue(text(image?.attributes['style']), 'height'),
      ),
      link = TextEditingController(
        text: image?.parent?.localName == 'a'
            ? image?.parent?.attributes['href']
            : '',
      );
  late bool blur = image?.classes.contains('blur-img') ?? false;
  String? error;
  @override
  void dispose() {
    for (final c in [src, alt, width, height, link]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('图片设置'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _input(src, '图片地址（替换图片）'),
            if (widget.uploadImage != null)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final url = await widget.uploadImage!();
                    if (mounted && url != null) src.text = url;
                  },
                  icon: const Icon(Icons.upload_outlined),
                  label: const Text('从设备选择替换图片'),
                ),
              ),
            _input(alt, '图片说明'),
            Row(
              children: [
                Expanded(child: _input(width, '宽度（像素或百分比）')),
                const SizedBox(width: 12),
                Expanded(child: _input(height, '高度（像素或百分比）')),
              ],
            ),
            _input(link, '图片链接（留空移除）'),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  try {
                    final url = extraWeb(link.text);
                    if (!await launchUrl(
                          Uri.parse(url),
                          mode: LaunchMode.externalApplication,
                        ) &&
                        mounted) {
                      setState(() => error = '没有可打开的应用');
                    }
                  } catch (e) {
                    if (mounted) setState(() => error = e.toString());
                  }
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('打开图片链接'),
              ),
            ),
            SwitchListTile(
              value: blur,
              onChanged: (v) => setState(() => blur = v),
              title: const Text('图片模糊化'),
            ),
            _error(error),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('删除这张图片？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('删除'),
                ),
              ],
            ),
          );
          if (ok == true && context.mounted) Navigator.pop(context, '');
        },
        child: const Text('删除图片'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          try {
            Navigator.pop(
              context,
              extraUpdateImage(
                widget.original,
                src: src.text,
                alt: alt.text,
                width: width.text,
                height: height.text,
                blur: blur,
                link: link.text,
              ),
            );
          } catch (e) {
            setState(() => error = e.toString());
          }
        },
        child: const Text('应用'),
      ),
    ],
  );
}

class _ReferenceDialog extends StatefulWidget {
  final SiteApi api;
  final Json? account;
  final bool lottery;
  final Future<String?> Function()? uploadImage;
  const _ReferenceDialog({
    required this.api,
    this.account,
    this.lottery = false,
    this.uploadImage,
  });
  @override
  State<_ReferenceDialog> createState() => _ReferenceState();
}

class _ReferenceState extends State<_ReferenceDialog> {
  final search = TextEditingController();
  List<Json> items = [];
  int page = 1, pages = 1, request = 0;
  late final accountGeneration = widget.api.generation;
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    request++;
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (widget.api.generation != accountGeneration) {
      setState(() {
        loading = false;
        error = '账号已切换，请关闭后重试';
      });
      return;
    }
    final run = ++request;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await widget.api.get(
        widget.lottery ? 'lottery/list' : 'poll/list',
        {
          'page': page,
          'per_page': 15,
          if (!widget.lottery) 'user_id': number(widget.account?['id']),
          if (search.text.trim().isNotEmpty) 'search': search.text.trim(),
          'include': 'user',
        },
      );
      if (!mounted ||
          run != request ||
          widget.api.generation != accountGeneration) {
        return;
      }
      setState(() {
        items = rows(r['data']);
        pages = number(object(object(r['meta'])['pagination'])['total_pages'])
            .clamp(1, 100000);
        loading = false;
      });
    } catch (e) {
      if (!mounted ||
          run != request ||
          widget.api.generation != accountGeneration) {
        return;
      }
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> edit([Json? item]) async {
    try {
      if (widget.api.generation != accountGeneration) {
        throw const FormatException('账号已切换，请关闭后重试');
      }
      Json? initial;
      if (item != null) {
        final r = await widget.api.get('poll/info', {'id': item['id']});
        initial = object(r['data']);
      }
      if (!mounted || widget.api.generation != accountGeneration) return;
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PollDialog(
          api: widget.api,
          account: widget.account,
          initial: initial,
          accountGeneration: accountGeneration,
          uploadImage: widget.uploadImage,
        ),
      );
      if (saved == true && mounted) load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.lottery ? '插入抽奖' : '插入我的投票'),
    content: SizedBox(
      width: 760,
      height: 520,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: search,
                  onSubmitted: (_) {
                    page = 1;
                    load();
                  },
                  decoration: InputDecoration(
                    labelText: '搜索主题',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: '搜索',
                      onPressed: () {
                        page = 1;
                        load();
                      },
                      icon: const Icon(Icons.search),
                    ),
                  ),
                ),
              ),
              if (!widget.lottery &&
                  extraNamed(widget.account, 'permissions', 'edit_polls')) ...[
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: loading ? null : () => edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('创建投票'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (error != null) _error(error),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                ? const Center(child: Text('暂无可插入的内容'))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ListTile(
                        isThreeLine: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '#${item['id']}  ${item[widget.lottery ? 'name' : 'title']}',
                        ),
                        subtitle: Text(
                          widget.lottery
                              ? (item['is_finished'] == true ? '已开奖' : '未开奖')
                              : '${item['image_mode'] == true ? '图片模式' : '文本模式'} · ${item['multi_select'] == true ? '多选' : '单选'}',
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            if (!widget.lottery &&
                                extraNamed(
                                  widget.account,
                                  'permissions',
                                  'edit_polls',
                                ))
                              IconButton(
                                tooltip: '修改投票',
                                onPressed: () => edit(item),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                            FilledButton.tonal(
                              onPressed: () {
                                if (widget.api.generation !=
                                    accountGeneration) {
                                  setState(() => error = '账号已切换，请关闭后重试');
                                  return;
                                }
                                Navigator.pop(
                                  context,
                                  extraReference(
                                    widget.lottery ? 'lottery' : 'poll',
                                    number(item['id']),
                                  ),
                                );
                              },
                              child: const Text('插入'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: '上一页',
                onPressed: loading || page <= 1
                    ? null
                    : () {
                        page--;
                        load();
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              Text('$page / $pages'),
              IconButton(
                tooltip: '下一页',
                onPressed: loading || page >= pages
                    ? null
                    : () {
                        page++;
                        load();
                      },
                icon: const Icon(Icons.chevron_right),
              ),
              if (error != null)
                TextButton(onPressed: load, child: const Text('重试')),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}

class _PollOption {
  final Json original;
  late final textInput = TextEditingController(text: text(original['text'])),
      image = TextEditingController(text: text(original['image']));
  _PollOption(this.original);
  void dispose() {
    textInput.dispose();
    image.dispose();
  }
}

class _PollDialog extends StatefulWidget {
  final SiteApi api;
  final Json? account, initial;
  final int accountGeneration;
  final Future<String?> Function()? uploadImage;
  const _PollDialog({
    required this.api,
    this.account,
    this.initial,
    required this.accountGeneration,
    this.uploadImage,
  });
  @override
  State<_PollDialog> createState() => _PollState();
}

class _PollState extends State<_PollDialog> {
  late final title = TextEditingController(
        text: text(widget.initial?['title']),
      ),
      max = TextEditingController(
        text: text(widget.initial?['max_select'], '0'),
      ),
      start = TextEditingController(text: text(widget.initial?['start_at'])),
      end = TextEditingController(text: text(widget.initial?['end_at']));
  late bool images = widget.initial?['image_mode'] == true,
      multi = widget.initial?['multi_select'] == true;
  late final options = rows(widget.initial?['options'])
      .map(_PollOption.new)
      .toList();
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    while (options.length < 2) {
      options.add(_PollOption({}));
    }
  }

  @override
  void dispose() {
    for (final c in [title, max, start, end]) {
      c.dispose();
    }
    for (final o in options) {
      o.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    try {
      if (widget.api.generation != widget.accountGeneration) {
        throw const FormatException('账号已切换，请关闭后重试');
      }
      if (!extraNamed(widget.account, 'permissions', 'edit_polls')) {
        throw const FormatException('此账号没有编辑投票权限');
      }
      final payload = extraPollPayload({
        'id': widget.initial?['id'],
        'title': title.text,
        'options': [
          for (final o in options)
            {...o.original, 'text': o.textInput.text, 'image': o.image.text},
        ],
        'image_mode': images,
        'multi_select': multi,
        'max_select': max.text,
        'start_at': start.text,
        'end_at': end.text,
      });
      setState(() {
        saving = true;
        error = null;
      });
      await widget.api.post(
        widget.initial == null ? 'poll/create' : 'poll/update',
        payload,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: Text(widget.initial == null ? '创建投票' : '修改投票'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: AbsorbPointer(
            absorbing: saving,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _input(title, '投票主题'),
                SwitchListTile(
                  value: images,
                  onChanged: (v) => setState(() => images = v),
                  title: const Text('图片模式（每项需图片）'),
                ),
                for (var i = 0; i < options.length; i++)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text('选项 ${i + 1}')),
                              IconButton(
                                tooltip: '移除此选项',
                                onPressed: options.length <= 2
                                    ? null
                                    : () {
                                        final removed = options[i];
                                        setState(() => options.remove(removed));
                                        WidgetsBinding.instance
                                            .addPostFrameCallback(
                                              (_) => removed.dispose(),
                                            );
                                      },
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                          _input(options[i].textInput, '选项文字'),
                          if (images)
                            _input(
                              options[i].image,
                              '图片地址',
                              suffix: widget.uploadImage == null
                                  ? null
                                  : IconButton(
                                      tooltip: '上传选项图片',
                                      onPressed: () async {
                                        final item = options[i];
                                        final url = await widget.uploadImage!();
                                        if (mounted &&
                                            options.contains(item) &&
                                            url != null) {
                                          item.image.text = url;
                                        }
                                      },
                                      icon: const Icon(Icons.upload_outlined),
                                    ),
                            ),
                        ],
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        setState(() => options.add(_PollOption({}))),
                    icon: const Icon(Icons.add),
                    label: const Text('增加选项'),
                  ),
                ),
                SwitchListTile(
                  value: multi,
                  onChanged: (v) => setState(() => multi = v),
                  title: const Text('允许多选'),
                ),
                if (multi) _input(max, '多选上限（0 不限）'),
                _input(start, '开始时间（可空，yyyy-MM-dd HH:mm:ss）'),
                _input(end, '截止时间（可空）'),
                const Text('保存将立即在官网创建或修改投票；正文仍需单独点击插入。'),
                _error(error),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? '正在保存…' : '保存到官网'),
        ),
      ],
    ),
  );
}

class _TableDialog extends StatefulWidget {
  final String original;
  const _TableDialog(this.original);
  @override
  State<_TableDialog> createState() => _TableState();
}

class _TableState extends State<_TableDialog> {
  late final table = html.parseFragment(widget.original).querySelector('table');
  late final oldRows = table?.querySelectorAll('tr') ?? [];
  late int r = table == null ? 2 : oldRows.length.clamp(1, 30),
      c = table == null
          ? 2
          : oldRows.fold<int>(
              1,
              (v, row) => v > row.children.length ? v : row.children.length,
            );
  late final rowsInput = TextEditingController(text: '$r'),
      colsInput = TextEditingController(text: '$c');
  late final width = TextEditingController(
        text: extraStyleValue(text(table?.attributes['style']), 'width'),
      ),
      height = TextEditingController(
        text: extraStyleValue(text(table?.attributes['style']), 'height'),
      );
  late String align =
      ['left', 'center', 'right'].contains(
        extraStyleValue(text(table?.attributes['style']), 'text-align'),
      )
      ? extraStyleValue(text(table?.attributes['style']), 'text-align')
      : 'left';
  late String border = ['dashed', 'dotted', 'none'].firstWhere(
    (b) =>
        extraStyleValue(text(table?.attributes['style']), 'border').contains(b),
    orElse: () => 'solid',
  );
  final cells = <TextEditingController>[];
  String? error;
  @override
  void initState() {
    super.initState();
    for (var i = 0; i < r; i++) {
      for (var j = 0; j < c; j++) {
        cells.add(
          TextEditingController(
            text: i < oldRows.length && j < oldRows[i].children.length
                ? oldRows[i].children[j].text
                : '',
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final input in [rowsInput, colsInput, width, height, ...cells]) {
      input.dispose();
    }
    super.dispose();
  }

  void resize() {
    try {
      final nr = int.parse(rowsInput.text), nc = int.parse(colsInput.text);
      if (nr < 1 || nr > 30 || nc < 1 || nc > 12 || nr * nc > 180) {
        throw const FormatException('最多 30 行、12 列、180 格');
      }
      final previous = cells.toList(), values = <String>[];
      for (var i = 0; i < nr; i++) {
        for (var j = 0; j < nc; j++) {
          values.add(i < r && j < c ? previous[i * c + j].text : '');
        }
      }
      setState(() {
        cells.clear();
        cells.addAll(values.map((v) => TextEditingController(text: v)));
        r = nr;
        c = nc;
        error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final input in previous) {
          input.dispose();
        }
      });
    } catch (e) {
      setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(table == null ? '插入表格' : '编辑表格'),
    content: SizedBox(
      width: 680,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: _input(rowsInput, '行数（最多 30）')),
                const SizedBox(width: 12),
                Expanded(child: _input(colsInput, '列数（最多 12）')),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: resize,
                child: const Text('应用行列数'),
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < r; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var j = 0; j < c; j++)
                        SizedBox(
                          width: 180,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _input(
                              cells[i * c + j],
                              '第 ${i + 1} 行 · 第 ${j + 1} 列',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(child: _input(width, '表格宽度（如 100% 或 600）')),
                const SizedBox(width: 12),
                Expanded(child: _input(height, '表格高度（留空自动）')),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: border,
                    decoration: const InputDecoration(labelText: '边框'),
                    items: const [
                      DropdownMenuItem(value: 'solid', child: Text('实线')),
                      DropdownMenuItem(value: 'dashed', child: Text('虚线')),
                      DropdownMenuItem(value: 'dotted', child: Text('点线')),
                      DropdownMenuItem(value: 'none', child: Text('无边框')),
                    ],
                    onChanged: (v) => setState(() => border = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: align,
                    decoration: const InputDecoration(labelText: '对齐'),
                    items: const [
                      DropdownMenuItem(value: 'left', child: Text('靠左')),
                      DropdownMenuItem(value: 'center', child: Text('居中')),
                      DropdownMenuItem(value: 'right', child: Text('靠右')),
                    ],
                    onChanged: (v) => setState(() => align = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('未修改的单元格保留原有文字样式和链接。合并或嵌套表格请使用源码模式。'),
            _error(error),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          try {
            if (int.parse(rowsInput.text) != r ||
                int.parse(colsInput.text) != c) {
              throw const FormatException('请先点击应用行列数');
            }
            Navigator.pop(
              context,
              extraTable(
                widget.original,
                rowCount: r,
                columnCount: c,
                cells: cells.map((e) => e.text).toList(),
                width: width.text,
                height: height.text,
                border: border,
                align: align,
              ),
            );
          } catch (e) {
            setState(() => error = e.toString());
          }
        },
        child: const Text('应用'),
      ),
    ],
  );
}
