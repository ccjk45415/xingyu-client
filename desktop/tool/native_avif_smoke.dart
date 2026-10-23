import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_avif_platform_interface/flutter_avif_platform_interface.dart';
import 'package:xingyu_desktop/core/image_codec.dart';

void main() {
  testWidgets('real native AVIF decoder handles static and Steam AVIF bytes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final root = Directory(Directory.current.resolveSymbolicLinksSync())
          .parent
          .path;
      FlutterAvifPlatform.api = FlutterAvifImpl(
        DynamicLibrary.open(
          '$root/desktop/windows/flutter/ephemeral/.plugin_symlinks/flutter_avif_windows/windows/flutter_avif.dll',
        ),
      );
      final results = <Map<String, dynamic>>[];
      for (final name in [
        'synthetic.avif',
        'steam-banner-0.avif',
        'steam-banner-1.avif',
        'steam-banner-2.avif',
      ]) {
        final bytes = await File('build/video-smoke/$name').readAsBytes();
        expect(isAvif(bytes), true);
        final codec = await AvifUiCodec.create(bytes);
        final decoded = await codec.getNextFrame();
        expect(decoded.image.width, greaterThan(0));
        expect(decoded.image.height, greaterThan(0));
        if (name.startsWith('synthetic')) {
          expect(decoded.image.width, 160);
          expect(decoded.image.height, 90);
        }
        results.add({
          'fixture': name,
          'width': decoded.image.width,
          'height': decoded.image.height,
          'frames': codec.frameCount,
        });
        decoded.image.dispose();
        codec.dispose();
      }
      await File('$root/evidence/avif-native-decoder-validation.json')
          .writeAsString(
            jsonEncode({
              'codec': 'libavif',
              'browser_used': false,
              'actual_steam_images_decoded': 3,
              'images': results,
            }),
          );
    });
  });
}
