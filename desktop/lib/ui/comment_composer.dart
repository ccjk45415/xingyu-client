import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image;

import '../core/api.dart';
import '../core/comment_content.dart';
import '../core/state.dart';
import 'shared.dart';

const commentImageLimit = 1024 * 1024;
const _imageClipboard = MethodChannel('moe.cangku.xingyu/image_clipboard');

void validateCommentImage(Uint8List bytes) {
  if (bytes.length > commentImageLimit) throw ApiFailure(413, '评论图片不能超过 1 MB');
  final (extension, _) = uploadImageType(bytes);
  if (extension == 'jpg' &&
      (bytes.length < 3 ||
          bytes[0] != 0xff ||
          bytes[1] != 0xd8 ||
          bytes[2] != 0xff)) {
    throw ApiFailure(400, '只支持 JPG、PNG、GIF、WebP 图片');
  }
  final info = image.findDecoderForData(bytes)?.startDecode(bytes);
  if (info == null ||
      info.width < 1 ||
      info.height < 1 ||
      info.width * info.height > 40000000) {
    throw ApiFailure(400, '图片格式无效或尺寸过大');
  }
}

Future<String?> composeComment(BuildContext context, String title) async {
  final app = stateOf(context), owner = stateOf(context).uid;
  final generation = app.generation, session = app.site.generation;
  final value = await showDialog<String>(
    context: context,
    builder: (_) => _CommentComposer(
      app: app,
      owner: owner,
      title: title,
      generation: generation,
      session: session,
    ),
  );
  return context.mounted &&
          app.uid == owner &&
          app.generation == generation &&
          app.site.generation == session
      ? value
      : null;
}

class _CommentComposer extends StatefulWidget {
  final AppState app;
  final int owner, generation, session;
  final String title;
  const _CommentComposer({
    required this.app,
    required this.owner,
    required this.title,
    required this.generation,
    required this.session,
  });
  @override
  State<_CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<_CommentComposer> {
  final controller = TextEditingController();
  final focus = FocusNode();
  int group = 0;
  bool stickers = false, preview = false, busy = false;
  String? error;
  bool get active =>
      mounted &&
      widget.app.uid == widget.owner &&
      widget.app.generation == widget.generation &&
      widget.app.site.generation == widget.session;
  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  bool insert(String value, {TextSelection? at}) {
    final current = controller.value;
    final selection = at ?? current.selection;
    final start = selection.isValid ? selection.start : current.text.length;
    final end = selection.isValid ? selection.end : start;
    if (current.text.length - (end - start) + value.length > 5000) {
      setState(() => error = '评论最多 5000 字符');
      return false;
    }
    controller.value = TextEditingValue(
      text: current.text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    focus.requestFocus();
    return true;
  }

  Future<void> upload(
    Uint8List bytes,
    TextSelection selection,
    String original,
  ) async {
    validateCommentImage(bytes);
    if (!active) return;
    final value = await widget.app.site.upload('upload/image', 'image', bytes);
    if (!active) return;
    final data = object(value['data']);
    var url = text(
      data['url'],
      text(data['link'], text(value['url'], text(value['link']))),
    );
    if (url.startsWith('/')) url = '$siteOrigin$url';
    final uri = Uri.tryParse(url);
    if (uri?.scheme != 'https' ||
        uri!.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw ApiFailure(400, '上传未返回有效图片地址');
    }
    if (controller.text != original) throw ApiFailure(409, '内容已变化，请重新插入图片');
    if (!insert(' $url ', at: selection)) {
      throw ApiFailure(400, '评论最多 5000 字符，请缩短内容后重新添加图片');
    }
    preview = true;
  }

  Future<bool> imageTask(Future<Uint8List?> Function() read) async {
    if (busy || !active) return true;
    final selection = controller.selection, original = controller.text;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final bytes = await read();
      if (!active || bytes == null) return false;
      await upload(bytes, selection, original);
      return true;
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PlatformException
              ? '无法粘贴图片：${e.message ?? '剪贴板不可用'}（图片不能超过 1 MB）'
              : e.toString(),
        );
      }
      return true;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> paste() async {
    final consumed = await imageTask(() async {
      try {
        return await _imageClipboard.invokeMethod<Uint8List>('readImage');
      } on MissingPluginException {
        return null;
      }
    });
    if (!consumed && active) {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (active && data?.text != null) setState(() => insert(data!.text!));
    }
  }

  Future<void> pick() => imageTask(() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: '评论图片（1 MB 以内）',
          extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp'],
        ),
      ],
    );
    if (file == null) return null;
    if (await file.length() > commentImageLimit) {
      throw ApiFailure(413, '评论图片不能超过 1 MB');
    }
    return file.readAsBytes();
  });

  @override
  Widget build(BuildContext context) {
    final selected = siteStickerGroups[group];
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Actions(
                actions: {
                  PasteTextIntent: CallbackAction<PasteTextIntent>(
                    onInvoke: (_) {
                      paste();
                      return null;
                    },
                  ),
                },
                child: TextField(
                  controller: controller,
                  focusNode: focus,
                  readOnly: busy,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 5000,
                  decoration: const InputDecoration(
                    hintText: '写下想说的话，可直接粘贴图片（1 MB 以内）',
                    border: OutlineInputBorder(),
                  ),
                  contextMenuBuilder: (c, editable) {
                    final items = editable.contextMenuButtonItems
                        .where(
                          (item) => item.type != ContextMenuButtonType.paste,
                        )
                        .toList();
                    items.add(
                      ContextMenuButtonItem(
                        type: ContextMenuButtonType.paste,
                        label: '粘贴图片或文字',
                        onPressed: () {
                          editable.hideToolbar();
                          paste();
                        },
                      ),
                    );
                    return AdaptiveTextSelectionToolbar.buttonItems(
                      anchors: editable.contextMenuAnchors,
                      buttonItems: items,
                    );
                  },
                ),
              ),
              Wrap(
                spacing: 6,
                children: [
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : () => setState(() => stickers = !stickers),
                    icon: const Icon(Icons.emoji_emotions_outlined, size: 19),
                    label: const Text('官网表情'),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : pick,
                    icon: const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 19,
                    ),
                    label: const Text('添加图片'),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : paste,
                    icon: const Icon(Icons.content_paste_outlined, size: 19),
                    label: const Text('粘贴'),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => preview = !preview),
                    icon: const Icon(Icons.preview_outlined, size: 19),
                    label: Text(preview ? '收起预览' : '预览'),
                  ),
                ],
              ),
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (stickers) ...[
                Wrap(
                  spacing: 6,
                  children: [
                    for (var i = 0; i < siteStickerGroups.length; i++)
                      ChoiceChip(
                        label: Text(siteStickerGroups[i].name),
                        selected: group == i,
                        onSelected: busy
                            ? null
                            : (_) => setState(() => group = i),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 180,
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 52,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                        ),
                    itemCount: selected.count,
                    itemBuilder: (c, i) => Tooltip(
                      message: selected.token(i + 1),
                      child: InkWell(
                        onTap: busy
                            ? null
                            : () =>
                                  setState(() => insert(selected.token(i + 1))),
                        child: Padding(
                          padding: const EdgeInsets.all(7),
                          child: Image.network(
                            selected.url(i + 1),
                            headers: const {'Referer': '$siteOrigin/'},
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) =>
                                Center(child: Text('${i + 1}')),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              if (preview)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (_, value, _) => RichContent(
                      renderCommentContent(value.text),
                      fontSize: 15,
                      maxImageHeight: 220,
                      maxImageWidth: 480,
                    ),
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
        FilledButton(
          onPressed: busy
              ? null
              : () {
                  if (active && controller.text.trim().isNotEmpty) {
                    Navigator.pop(context, controller.text.trim());
                  }
                },
          child: const Text('发布'),
        ),
      ],
    );
  }
}
