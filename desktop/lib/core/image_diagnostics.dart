import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'image_codec.dart';

/// Explicit local fixture decoder check; no user account or network access.
Future<void> runImageSelfCheck(String fixture) async {
  try {
    final bytes = await File(fixture).readAsBytes();
    if (!isAvif(bytes)) throw const FormatException('AVIF fixture required');
    final codec = await AvifUiCodec.create(bytes);
    final frame = await codec.getNextFrame();
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(child: RawImage(image: frame.image)),
        ),
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    stdout.writeln(
      jsonEncode({
        'avif_decoded': true,
        'width': frame.image.width,
        'height': frame.image.height,
        'frames': codec.frameCount,
      }),
    );
    await stdout.flush();
    runApp(const SizedBox());
    await WidgetsBinding.instance.endOfFrame;
    frame.image.dispose();
    codec.dispose();
    exit(0);
  } catch (e) {
    stderr.writeln('AVIF check failed: ${e.runtimeType}');
    exit(1);
  }
}
