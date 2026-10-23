import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../ui/shared.dart';
import 'api.dart';
import 'state.dart';

Uint8List compressImage(Uint8List data) {
  final decoder = img.findDecoderForData(data),
      info = img.findDecoderForData(data)?.startDecode(data);
  if (info == null ||
      info.width <= 0 ||
      info.height <= 0 ||
      info.width * info.height > 40000000) {
    throw ApiFailure(413, '图片尺寸过大或格式不支持，请选择4000万像素以内的图片');
  }
  final decoded = decoder?.decode(data, frame: 0);
  if (decoded == null) throw ApiFailure(400, '图片格式暂不支持');
  final oriented = img.bakeOrientation(decoded);
  for (var edge = 1280; edge >= 300; edge = (edge * .72).floor()) {
    final ratio =
        edge /
        (oriented.width > oriented.height ? oriented.width : oriented.height);
    final image = ratio < 1
        ? img.copyResize(
            oriented,
            width: (oriented.width * ratio).round().clamp(1, 1280),
            height: (oriented.height * ratio).round().clamp(1, 1280),
          )
        : oriented;
    // New RGB pixels remove metadata; alpha is flattened onto white before encoding.
    final clean = img.Image(
      width: image.width,
      height: image.height,
      numChannels: 3,
    );
    img.fill(clean, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(clean, image);
    for (final quality in [85, 70, 55]) {
      final encoded = img.encodeJpg(clean, quality: quality);
      if (encoded.length <= 192 * 1024) return encoded;
    }
  }
  throw ApiFailure(413, '图片压缩后仍然过大，请选择较小的图片');
}

Future<Uint8List?> pickJpeg(BuildContext context) async {
  final file = await openFile(
    acceptedTypeGroups: [
      const XTypeGroup(
        label: '图片',
        extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
        mimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/bmp'],
      ),
    ],
  );
  if (file == null) return null;
  if (await file.length() > 20 * 1024 * 1024) {
    throw ApiFailure(413, '请选择20MB以内的图片');
  }
  final bytes = await compute(compressImage, await file.readAsBytes());
  if (!context.mounted) return null;
  final yes = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('使用这张图片？'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: Image.memory(bytes),
            ),
            const SizedBox(height: 16),
            Text(
              '压缩后 ${(bytes.length / 1024).ceil()} KB · 已去除EXIF信息\n动图只保留一帧',
              textAlign: TextAlign.center,
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
          child: const Text('确认添加'),
        ),
      ],
    ),
  );
  return yes == true ? bytes : null;
}

Future<Json> uploadChatImage(
  AppState app,
  Uint8List data,
  String scope,
  String target,
) async {
  final result = await app.service.send(
    '/media/v1/images?scope=$scope&target=$target',
    token: app.token,
    body: data,
    headers: {'X-Upload-ID': nonce()},
    type: 'image/jpeg',
  );
  return _decode(result);
}

// Keep only image metadata outside this helper; authenticated bytes stay in bounded memory.
Json _decode(Uint8List bytes) => object(_decodeJson(bytes)['image']);
Json _decodeJson(Uint8List bytes) => object(jsonDecode(utf8.decode(bytes)));

class MediaCache {
  static final _cache = <String, Uint8List>{};
  static int _bytes = 0, _owner = 0;
  static Future<Uint8List> get(AppState app, String id) async {
    if (_owner != app.uid) {
      _cache.clear();
      _bytes = 0;
      _owner = app.uid;
    }
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      throw ApiFailure(400, '图片编号无效');
    }
    final owner = app.uid, hit = _cache.remove(id);
    if (hit != null) {
      _cache[id] = hit;
      return hit;
    }
    final bytes = await app.service.send(
      '/media/v1/images/$id',
      token: app.token,
    );
    if (owner != app.uid || _owner != owner) throw ApiFailure(409, '账号已切换');
    _cache[id] = bytes;
    _bytes += bytes.length;
    while (_bytes > 16 * 1024 * 1024 && _cache.isNotEmpty) {
      _bytes -= _cache.remove(_cache.keys.first)!.length;
    }
    return bytes;
  }

  static void clear() {
    _cache.clear();
    _bytes = 0;
    _owner = 0;
  }
}

class ChatImage extends StatefulWidget {
  final Json image;
  const ChatImage(this.image, {super.key});
  @override
  State<ChatImage> createState() => _ChatImageState();
}

class _ChatImageState extends State<ChatImage> {
  Future<Uint8List>? future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future ??= MediaCache.get(stateOf(context), text(widget.image['id']));
  }

  @override
  void didUpdateWidget(covariant ChatImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image['id'] != widget.image['id']) {
      future = MediaCache.get(stateOf(context), text(widget.image['id']));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: future,
    builder: (c, snapshot) => ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 240,
        height: 180,
        child: snapshot.hasData
            ? QrImageActions(
                bytes: snapshot.data!,
                child: InkWell(
                  onTap: () => showImage(c, bytes: snapshot.data!),
                  child: Image.memory(
                    snapshot.data!,
                    fit: BoxFit.contain,
                    cacheWidth: 600,
                  ),
                ),
              )
            : snapshot.hasError
            ? TextButton(
                onPressed: () => setState(
                  () => future = MediaCache.get(
                    stateOf(context),
                    text(widget.image['id']),
                  ),
                ),
                child: const Text('图片已过期或加载失败\n点击重试'),
              )
            : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    ),
  );
}
