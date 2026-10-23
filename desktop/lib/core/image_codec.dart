import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_avif_platform_interface/flutter_avif_platform_interface.dart';

bool isAvif(Uint8List bytes) {
  if (bytes.length < 16 ||
      ascii.decode(bytes.sublist(4, 8), allowInvalid: true) != 'ftyp') {
    return false;
  }
  final size = ByteData.sublistView(bytes).getUint32(0).clamp(16, bytes.length);
  for (var at = 8; at + 4 <= size && at < 128; at += 4) {
    if (at == 12) continue; // minor version, not a compatible brand
    if ([
      'avif',
      'avis',
    ].contains(ascii.decode(bytes.sublist(at, at + 4), allowInvalid: true))) {
      return true;
    }
  }
  return false;
}

/// Shared by cached images, original-image viewer and AVIF video posters.
class AvifUiCodec implements ui.Codec {
  static int sequence = 0;
  final String key;
  @override
  final int frameCount;
  bool disposed = false;
  AvifUiCodec._(this.key, this.frameCount);
  static Future<AvifUiCodec> create(Uint8List bytes) async {
    final key = 'xingyu-${DateTime.now().microsecondsSinceEpoch}-${sequence++}';
    try {
      final info = await FlutterAvifPlatform.api
          .initMemoryDecoder(key: key, avifBytes: bytes)
          .timeout(const Duration(seconds: 20));
      // The bridge reports dimensions on decoded frames in some libavif builds.
      if (info.width * info.height > 64000000 ||
          info.imageCount <= 0 ||
          info.imageCount > 10000) {
        throw const FormatException('AVIF尺寸或帧数无效');
      }
      return AvifUiCodec._(key, info.imageCount);
    } catch (_) {
      unawaited(
        FlutterAvifPlatform.api
            .disposeDecoder(key: key)
            .catchError((_) => false),
      );
      rethrow;
    }
  }

  @override
  int get repetitionCount => frameCount > 1 ? -1 : 0;
  @override
  Future<ui.FrameInfo> getNextFrame() async {
    if (disposed) throw StateError('Image codec disposed');
    final frame = await FlutterAvifPlatform.api
        .getNextFrame(key: key)
        .timeout(const Duration(seconds: 20));
    if (frame.width <= 0 ||
        frame.height <= 0 ||
        frame.width * frame.height > 64000000 ||
        frame.data.length != frame.width * frame.height * 4) {
      throw const FormatException('AVIF帧数据无效');
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      Uint8List.fromList(frame.data),
      frame.width,
      frame.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    if (disposed) {
      image.dispose();
      throw StateError('Image codec disposed');
    }
    return _Frame(
      image,
      Duration(milliseconds: (frame.duration * 1000).round().clamp(0, 60000)),
    );
  }

  @override
  void dispose() {
    if (disposed) return;
    disposed = true;
    unawaited(
      FlutterAvifPlatform.api.disposeDecoder(key: key).catchError((_) => false),
    );
  }
}

class _Frame implements ui.FrameInfo {
  @override
  final ui.Image image;
  @override
  final Duration duration;
  _Frame(this.image, this.duration);
}
