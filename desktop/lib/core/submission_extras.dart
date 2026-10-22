import 'dart:convert';

import 'api.dart';

/// Local metadata only: never added to model prompts or translation segments.
String withDlsiteIds(String title, Iterable<String> urls) {
  final ids = <String>{};
  for (final raw in urls) {
    final u = Uri.tryParse(raw);
    if (u == null ||
        u.scheme != 'https' ||
        u.userInfo.isNotEmpty ||
        !(u.host == 'dlsite.com' || u.host.endsWith('.dlsite.com'))) {
      continue;
    }
    final match = RegExp(
      r'/product_id/(RJ[0-9]{6,12})(?:\.html)?(?:/|$)',
      caseSensitive: false,
    ).firstMatch(u.path);
    if (match != null) ids.add(match[1]!.toUpperCase());
  }
  var result = title.trim();
  if (result.isEmpty) return result;
  for (final id in ids) {
    if (!RegExp('\\[\\s*$id\\s*\\]', caseSensitive: false).hasMatch(result)) {
      result += ' [$id]';
    }
  }
  return result;
}

// Consume HTML attributes/comments/code as units: example shortcodes are not downloads.
final _tokens = RegExp(
  r'''<!--[\s\S]*?(?:-->|$)|<(pre|code|script|style)\b[^>]*>[\s\S]*?(?:</\1\s*>|$)|<div\b[^>]*\bdata-xingyu-purchase-proof=["']1["'][^>]*>[\s\S]*?</div\s*>|<(?:[^<>"']|"[^"]*"|'[^']*')*>|\[dlbox\b[^\]]*\]''',
  caseSensitive: false,
);

String placePurchaseProof(String body, String url) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw ApiFailure(400, '请先上传有效的自购证明图片');
  }
  // Replace only our own previous proof block; preserve the remaining source bytes.
  final out = StringBuffer();
  var cursor = 0;
  for (final m in _tokens.allMatches(body)) {
    if (m[0]!.toLowerCase().startsWith('<div') &&
        RegExp(
          r'''\bdata-xingyu-purchase-proof=["']1["']''',
          caseSensitive: false,
        ).hasMatch(m[0]!)) {
      out.write(body.substring(cursor, m.start));
      cursor = m.end;
    }
  }
  out.write(body.substring(cursor));
  final clean = out.toString();
  final index = _downloadIndex(clean);
  final proof =
      '<div data-xingyu-purchase-proof="1"><p>自购证明</p><p><img src="${const HtmlEscape().convert(url)}" alt="自购证明"></p></div>';
  return '${clean.substring(0, index)}\n$proof\n${clean.substring(index)}';
}

int _downloadIndex(String body) {
  var index = body.length;
  for (final m in _tokens.allMatches(body)) {
    if (m[0]!.toLowerCase().startsWith('[dlbox')) {
      index = m.start;
      // Official/visual editors may put a shortcode in its own paragraph.
      final p = RegExp(
        r'<p\b[^>]*>\s*$',
        caseSensitive: false,
      ).firstMatch(body.substring(0, index));
      if (p != null) index = p.start;
      break;
    }
  }
  return index;
}

String mergeSubmissionBody(
  String previous,
  String incoming,
  bool append,
  String? proof,
) {
  if (!append || previous.isEmpty) {
    return proof == null ? incoming : placePurchaseProof(incoming, proof);
  }
  if (proof == null) return '$previous\n$incoming';
  final index = _downloadIndex(previous);
  return placePurchaseProof(
    '${previous.substring(0, index)}\n$incoming\n${previous.substring(index)}',
    proof,
  );
}
