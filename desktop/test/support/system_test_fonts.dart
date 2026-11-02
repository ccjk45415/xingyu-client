import 'dart:io';

import 'package:flutter/services.dart';

/// Widget tests use Ahem unless fonts are explicitly loaded. Register native
/// text fonts under the app's fallback names so macOS tests measure real glyphs.
Future<void> loadSystemTestFonts() async {
  final candidates = Platform.isMacOS
      ? const [
          '/System/Library/Fonts/PingFang.ttc',
          '/System/Library/Fonts/Language Support/PingFang.ttc',
          '/System/Library/Fonts/Supplemental/Arial.ttf',
          '/System/Library/Fonts/Helvetica.ttc',
        ]
      : const ['C:/Windows/Fonts/msyh.ttc'];
  File? font;
  for (final path in candidates) {
    if (File(path).existsSync()) {
      font = File(path);
      break;
    }
  }
  if (font == null && (Platform.isMacOS || Platform.isWindows)) {
    throw StateError('A native text font is required for layout tests');
  }
  if (font != null) {
    final bytes = ByteData.sublistView(await font.readAsBytes());
    for (final family in [
      'Microsoft YaHei UI',
      'Microsoft YaHei',
      'Segoe UI',
    ]) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
  }
  final sdk = Platform.environment['FLUTTER_ROOT'];
  for (final path in [
    if (sdk != null)
      '$sdk/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    'C:/codex-tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  ]) {
    final icons = File(path);
    if (!icons.existsSync()) continue;
    await (FontLoader(
      'MaterialIcons',
    )..addFont(icons.readAsBytes().then(ByteData.sublistView))).load();
    break;
  }
}
