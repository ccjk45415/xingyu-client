import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;

import '../core/api.dart';

String shortcodeAttribute(String value) {
  if (value.contains(RegExp(r'[\r\n]'))) {
    throw const FormatException('字段不能包含换行');
  }
  return value
      .replaceAll('[', '【')
      .replaceAll(']', '】')
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;');
}

String downloadTemplate({
  required String title,
  String time = '',
  String source = '',
  String code = '',
  String password = '',
  String existingInfo = '',
  Map<String, String> extraAttributes = const {},
  required List<({String name, String url})> links,
}) {
  if (title.trim().isEmpty) throw const FormatException('请填写下载链接标题');
  if (links.isEmpty || links.any((v) => v.url.trim().isEmpty)) {
    throw const FormatException('请填写下载链接');
  }
  final generatedInfo = [
    if (code.trim().isNotEmpty) '提取：${code.trim()}',
    if (password.trim().isNotEmpty) '密码：${password.trim()}',
  ].join(' / ');
  final info = existingInfo.isNotEmpty ? existingInfo : generatedInfo;
  final attrs = <String, String>{
    'title': title.trim(),
    'time': time.trim(),
    'info': info,
    'from': source.trim(),
  };
  for (var i = 0; i < links.length; i++) {
    final link = links[i], url = link.url.trim();
    if (!safeExternal(url) && !url.startsWith('aliyunpan://')) {
      throw const FormatException('请输入有效下载地址');
    }
    if (url.contains('|') || link.name.contains('|')) {
      throw const FormatException('链接名称与地址不能包含竖线');
    }
    attrs['link${i + 1}'] = '${link.name.trim()}|$url';
  }
  for (final entry in extraAttributes.entries) {
    if (!attrs.containsKey(entry.key) &&
        !RegExp(r'^link\d+$').hasMatch(entry.key)) {
      attrs[entry.key] = entry.value;
    }
  }
  return '[dlbox ${attrs.entries.map((e) => '${e.key}="${shortcodeAttribute(e.value)}"').join(' ')}][/dlbox]';
}

String rapidDownloadLink(String code, bool ali) {
  final clean = code.trim();
  if (clean.isEmpty) throw const FormatException('请输入秒传链接');
  if (RegExp(r'https?://', caseSensitive: false).hasMatch(clean)) {
    throw const FormatException('普通分享链接请直接填写到下载地址，不需要秒传转换');
  }
  return '${ali ? 'https://www.aliyundrive.com/drive/#alink=' : 'https://pan.baidu.com/#bdlink='}${base64Encode(utf8.encode(clean))}';
}

const externalServices = [
  'Youtube',
  'Bilibili视频',
  'Bilibili直播',
  'Twitch视频',
  'Twitch直播',
  'Twitcasting直播',
  '斗鱼直播',
  '网络视频（mp4、webm）',
  'Mixcloud',
  'AppleMusic',
  '网易云音乐',
  'SoundCloud',
  'chobit',
  '网络音频（wav、mp3、ogg）',
  'Steam',
  'TapTap',
  'Twitter',
  'Facebook',
  'Pixiv',
  'Imgur',
  'Streamja',
];

String externalTemplate(String raw) {
  final url = raw.trim();
  final uri = Uri.tryParse(url);
  if (!safeExternal(url) ||
      uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      url.contains(RegExp(r'[\[\]\r\n]'))) {
    throw const FormatException('请输入有效的 HTTP/HTTPS 外部链接');
  }
  return '[iframe]$url[/iframe]';
}

Future<String?> showExternalTemplateDialog(
  BuildContext context, {
  String initialUrl = '',
}) async {
  final url = TextEditingController(text: initialUrl);
  var error = '';
  final result = await showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('插入外部链接'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('editor.external.url'),
                  controller: url,
                  decoration: InputDecoration(
                    labelText: '外部链接',
                    errorText: error.isEmpty ? null : error,
                  ),
                ),
                const SizedBox(height: 16),
                const Text('插入的链接会由官网自动解析为嵌入组件；编辑器内仅显示链接卡片。'),
                const SizedBox(height: 12),
                SizedBox(
                  height: 270,
                  child: ListView(
                    children: [
                      for (final name in externalServices)
                        ListTile(
                          dense: true,
                          title: Text(name),
                          trailing: const Icon(
                            Icons.check_circle_outline,
                            color: Colors.green,
                            size: 18,
                          ),
                        ),
                    ],
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
                Navigator.pop(c, externalTemplate(url.text));
              } catch (e) {
                set(() => error = '$e'.replaceFirst('FormatException: ', ''));
              }
            },
            child: const Text('插入'),
          ),
        ],
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 250));
  url.dispose();
  return result;
}

Future<String?> showDownloadTemplateDialog(
  BuildContext context, {
  String initialMarkup = '',
}) async {
  final initial = <String, String>{};
  if (initialMarkup.startsWith('[dlbox')) {
    final bracket = initialMarkup.indexOf(']');
    if (bracket > 0) {
      final tag = html
          .parseFragment('<div ${initialMarkup.substring(6, bracket)}></div>')
          .children
          .firstOrNull;
      if (tag != null) {
        for (final entry in tag.attributes.entries) {
          initial[entry.key.toString()] = entry.value;
        }
      }
    }
  }
  final title = TextEditingController(text: initial['title']),
      time = TextEditingController(text: initial['time']),
      from = TextEditingController(text: initial['from']),
      code = TextEditingController(),
      password = TextEditingController(),
      existingInfo = TextEditingController(text: initial['info']);
  final links = <({TextEditingController name, TextEditingController url})>[];
  final linkEntries =
      initial.entries
          .where((e) => RegExp(r'^link\d+$').hasMatch(e.key))
          .toList()
        ..sort(
          (a, b) =>
              int.parse(a.key.substring(4))
                  .compareTo(int.parse(b.key.substring(4))),
        );
  for (final entry in linkEntries) {
    final value = entry.value;
    final divider = value.indexOf('|');
    links.add((
      name: TextEditingController(
        text: divider < 0 ? '' : value.substring(0, divider),
      ),
      url: TextEditingController(
        text: divider < 0 ? value : value.substring(divider + 1),
      ),
    ));
  }
  if (links.isEmpty) {
    links.add((name: TextEditingController(), url: TextEditingController()));
  }
  final removed = <TextEditingController>[];
  var error = '';
  String value(TextEditingController c) =>
      c.text.trim().isEmpty ? '未知' : c.text;
  String infoPreview() {
    final result = existingInfo.text.isNotEmpty
        ? existingInfo.text
        : [
            if (code.text.isNotEmpty) '提取：${code.text}',
            if (password.text.isNotEmpty) '密码：${password.text}',
          ].join(' / ');
    return result.isEmpty ? '未知' : result;
  }

  final result = await showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('插入下载链接'),
        content: SizedBox(
          width: 740,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: title,
                  onChanged: (_) => set(() {}),
                  decoration: const InputDecoration(labelText: '下载链接标题'),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final e in [
                      (time, '上传时间'),
                      (from, '文件来源'),
                      (code, '提取码'),
                      (password, '解压码'),
                    ])
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: e.$1,
                          onChanged: (_) => set(() {}),
                          decoration: InputDecoration(labelText: e.$2),
                        ),
                      ),
                  ],
                ),
                if (initialMarkup.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: existingInfo,
                    onChanged: (_) => set(() {}),
                    decoration: const InputDecoration(
                      labelText: '原有文件信息（留空后使用上方提取码与解压码）',
                    ),
                  ),
                ],
                for (final (i, link) in links.indexed) ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: Text('链接${i + 1}')),
                      if (links.length > 1)
                        IconButton(
                          tooltip: '删除链接',
                          onPressed: () => set(() {
                            removed.addAll([link.name, link.url]);
                            links.removeAt(i);
                          }),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                  TextField(
                    controller: link.name,
                    onChanged: (_) => set(() {}),
                    decoration: const InputDecoration(labelText: '名称'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: link.url,
                          decoration: const InputDecoration(labelText: '链接'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () async {
                          final rapid = TextEditingController();
                          var ali = false;
                          var rapidError = '';
                          final raw = await showDialog<String>(
                            context: c,
                            builder: (rc) => StatefulBuilder(
                              builder: (rc, rs) => AlertDialog(
                                title: const Text('添加秒传链接'),
                                content: SizedBox(
                                  width: 480,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SegmentedButton<bool>(
                                        segments: const [
                                          ButtonSegment(
                                            value: false,
                                            label: Text('百度网盘'),
                                          ),
                                          ButtonSegment(
                                            value: true,
                                            label: Text('阿里云盘'),
                                          ),
                                        ],
                                        selected: {ali},
                                        onSelectionChanged: (v) =>
                                            rs(() => ali = v.first),
                                      ),
                                      const SizedBox(height: 16),
                                      TextField(
                                        controller: rapid,
                                        minLines: 3,
                                        maxLines: 8,
                                        decoration: InputDecoration(
                                          labelText: '粘贴秒传代码（支持多行）',
                                          errorText: rapidError.isEmpty
                                              ? null
                                              : rapidError,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(rc),
                                    child: const Text('取消'),
                                  ),
                                  FilledButton(
                                    onPressed: () {
                                      try {
                                        Navigator.pop(
                                          rc,
                                          rapidDownloadLink(rapid.text, ali),
                                        );
                                      } catch (e) {
                                        rs(
                                          () => rapidError = '$e'.replaceFirst(
                                            'FormatException: ',
                                            '',
                                          ),
                                        );
                                      }
                                    },
                                    child: const Text('添加'),
                                  ),
                                ],
                              ),
                            ),
                          );
                          await Future<void>.delayed(
                            const Duration(milliseconds: 250),
                          );
                          rapid.dispose();
                          if (raw != null && c.mounted) {
                            set(() => link.url.text = raw);
                          }
                        },
                        child: const Text('添加秒传链接'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                const Text('预览'),
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xfff3faff),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        color: const Color(0xffdcf3ff),
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          title.text.trim().isEmpty
                              ? '忘写标题了啊 Baka!'
                              : title.text,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '上传时间　${value(time)}\n文件来源　${value(from)}\n文件信息　${infoPreview()}',
                        ),
                      ),
                      Container(
                        color: const Color(0xff75c976),
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          links
                              .map(
                                (l) =>
                                    l.name.text.isEmpty ? '下载链接' : l.name.text,
                              )
                              .join('　｜　'),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                if (error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error,
                      style: TextStyle(color: Theme.of(c).colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: links.length >= 20
                ? null
                : () => set(
                    () => links.add((
                      name: TextEditingController(),
                      url: TextEditingController(),
                    )),
                  ),
            icon: const Icon(Icons.add),
            label: const Text('增加链接'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              try {
                Navigator.pop(
                  c,
                  downloadTemplate(
                    title: title.text,
                    time: time.text,
                    source: from.text,
                    code: code.text,
                    password: password.text,
                    existingInfo: existingInfo.text,
                    extraAttributes: initial,
                    links: links
                        .map((l) => (name: l.name.text, url: l.url.text))
                        .toList(),
                  ),
                );
              } catch (e) {
                set(() => error = '$e'.replaceFirst('FormatException: ', ''));
              }
            },
            child: const Text('插入'),
          ),
        ],
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 250));
  for (final controller in [
    title,
    time,
    from,
    code,
    password,
    existingInfo,
    ...removed,
    ...links.expand((l) => [l.name, l.url]),
  ]) {
    controller.dispose();
  }
  return result;
}
