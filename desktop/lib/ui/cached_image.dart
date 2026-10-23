import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/browse_cache.dart';
import '../core/image_codec.dart';

/// Shares Flutter's decoded image keys with NetworkImage and persists raw bytes.
class DiskImage extends ImageProvider<NetworkImage> {
  final String url;
  final Map<String, String>? headers;
  const DiskImage(this.url, {this.headers});
  @override
  Future<NetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(NetworkImage(url, headers: headers));
  @override
  ImageStreamCompleter loadImage(
    NetworkImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _decode(key, decode),
    scale: key.scale,
  );
  Future<ui.Codec> _decode(
    NetworkImage key,
    ImageDecoderCallback decode,
  ) async {
    try {
      final bytes = await BrowseCache.shared.image(url, headers: headers);
      if (isAvif(bytes)) return await AvifUiCodec.create(bytes);
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    }
  }
}

class CachedImage extends StatelessWidget {
  final String url;
  final Map<String, String>? headers;
  final double? width, height;
  final BoxFit? fit;
  final int? cacheWidth;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;
  const CachedImage(
    this.url, {
    super.key,
    this.headers,
    this.width,
    this.height,
    this.fit,
    this.cacheWidth,
    this.errorBuilder,
    this.loadingBuilder,
  });
  @override
  Widget build(BuildContext context) {
    final ImageProvider image = DiskImage(url, headers: headers);
    return Image(
      image: ResizeImage.resizeIfNeeded(cacheWidth, null, image),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder,
      loadingBuilder: loadingBuilder,
      gaplessPlayback: true,
    );
  }
}
