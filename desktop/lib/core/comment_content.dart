import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

/// The website's one-based sticker codes, shared by display and composition.
class SiteStickerGroup {
  final String id, name, extension;
  final int count;
  const SiteStickerGroup(
    this.id,
    this.name,
    this.count, [
    this.extension = 'png',
  ]);
  String token(int index) => '[$id:$index]';
  String url(int index) =>
      'https://cangku.moe/images/stickers/$id/$index.$extension';
}

const siteStickerGroups = [
  SiteStickerGroup('cangku_1', '仓库娘', 9),
  SiteStickerGroup('new_paopao', '新版泡泡', 66),
  SiteStickerGroup('paopao', '泡泡', 33),
  SiteStickerGroup('qq', 'QQ', 92, 'gif'),
  SiteStickerGroup('aru', 'aru', 122),
];

bool isCommentImageUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      ['https', 'http'].contains(uri.scheme) &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      RegExp(
        r'\.(?:png|jpe?g|gif|webp|bmp|avif)$',
        caseSensitive: false,
      ).hasMatch(uri.path);
}

/// Only transform text nodes, so URLs inside attributes/code cannot corrupt HTML.
/// Unknown sticker codes remain visible rather than requesting arbitrary paths.
String renderCommentContent(String source) {
  final root = html.parseFragment(source);
  final pattern = RegExp(
    r'\r?\n|\[([a-zA-Z0-9_]+):(\d+)\]|https?://[^\s<>"\x27\[\]，。；！？、“”]+',
  );
  void visit(Node node) {
    if (node is Element &&
        ['script', 'style', 'pre', 'code', 'a'].contains(node.localName)) {
      return;
    }
    if (node is! Text) {
      for (final child in node.nodes.toList()) {
        visit(child);
      }
      return;
    }
    final raw = node.data;
    final replacements = <Node>[];
    var offset = 0;
    for (final match in pattern.allMatches(raw)) {
      Element? image;
      var matched = match[0]!;
      if (matched == '\n' || matched == '\r\n') {
        image = Element.tag('br');
      } else if (match[1] != null) {
        final group = siteStickerGroups.where((g) => g.id == match[1]);
        final index = int.tryParse(match[2]!) ?? 0;
        if (group.isNotEmpty && index >= 1 && index <= group.first.count) {
          image = Element.tag('img')
            ..attributes.addAll({
              'src': group.first.url(index),
              'class': 'xingyu-site-sticker',
              'alt': matched,
              'width': '32',
              'height': '32',
            });
        }
      } else {
        // Do not include prose punctuation immediately following a pasted URL.
        matched = matched.replaceFirst(RegExp(r'[.,;!?)，。；！）]+$'), '');
        if (isCommentImageUrl(matched)) {
          image = Element.tag('img')
            ..attributes['src'] = matched
            ..attributes['alt'] = '评论图片';
        }
      }
      if (image == null) continue;
      replacements.add(Text(raw.substring(offset, match.start)));
      replacements.add(image);
      offset = match.start + matched.length;
    }
    if (replacements.isEmpty) return;
    replacements.add(Text(raw.substring(offset)));
    final parent = node.parentNode!;
    for (final replacement in replacements) {
      parent.insertBefore(replacement, node);
    }
    node.remove();
  }

  for (final img in root.querySelectorAll('img')) {
    final raw = img.attributes['src'] ?? '';
    if (raw.startsWith('/')) {
      img.attributes['src'] = Uri.parse('https://cangku.moe')
          .resolve(raw)
          .toString();
    }
  }
  visit(root);
  return root.outerHtml;
}
