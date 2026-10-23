/// Remove empty editing scaffolding without serializing untouched HTML. Media,
/// shortcodes, code examples and custom elements keep their original bytes.
String removeEmptyEditingMarkup(String source) {
  final protected = <String>[];
  var marker = 'XINGYU_EMPTY_GUARD_';
  while (source.contains(marker)) {
    marker += '_';
  }
  var result = source.replaceAllMapped(
    RegExp(
      r'<(pre|code|script|style|textarea)\b[^>]*>[\s\S]*?</\1\s*>|<!--[\s\S]*?-->|\[(dlbox|iframe|collapse|poll|lottery)\b[^\]]*\][\s\S]*?\[/\2\]',
      caseSensitive: false,
    ),
    (m) {
      protected.add(m[0]!);
      return '$marker${protected.length - 1}_END';
    },
  );
  final empty = RegExp(
    r'''<(p|div|section|article|h[1-6]|ul|ol|li|blockquote|a|span|b|strong|i|em|u|s|del|sup|sub)\b(?:[^<>"']|"[^"]*"|'[^']*')*>(?:\s|\u00a0|\u200b|\ufeff|&(?:nbsp|#160|#xA0);|<br\s*/?>)*</\1\s*>''',
    caseSensitive: false,
  );
  while (true) {
    final next = result.replaceAll(empty, '');
    if (next == result) break;
    result = next;
  }
  for (var i = 0; i < protected.length; i++) {
    result = result.replaceAll('$marker${i}_END', protected[i]);
  }
  return result;
}
