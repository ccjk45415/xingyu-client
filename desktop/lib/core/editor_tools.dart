import 'dart:convert';
import 'dart:math';

class EditorSnapshot {
  final String text;
  final int start, end;
  final bool html;
  const EditorSnapshot(this.text, this.start, this.end, {this.html = true});
  int get a => min(start, end).clamp(0, text.length);
  int get b => max(start, end).clamp(a, text.length);
  EditorSnapshot asHtml() {
    if (html) return this;
    String escaped(String s) => const HtmlEscape()
        .convert(s)
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\n', '<br>');
    return EditorSnapshot(
      '<p>${escaped(text)}</p>',
      3 + escaped(text.substring(0, a)).length,
      3 + escaped(text.substring(0, b)).length,
    );
  }
}

class EditorHistory {
  EditorSnapshot current;
  final List<EditorSnapshot> _undo = [], _redo = [];
  int _lastTyping = 0;
  EditorHistory(this.current);
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  void select(EditorSnapshot next) {
    current = next;
  }

  void record(EditorSnapshot next, {bool typing = false, int? now}) {
    if (next.text == current.text && next.html == current.html) {
      current = next;
      return;
    }
    final time = now ?? DateTime.now().millisecondsSinceEpoch;
    final merge =
        typing &&
        _lastTyping > 0 &&
        time - _lastTyping < 750 &&
        (next.text.length - current.text.length).abs() <= 2;
    if (!merge) _undo.add(current);
    current = next;
    _redo.clear();
    _lastTyping = typing ? time : 0;
    var chars = _undo.fold<int>(0, (n, e) => n + e.text.length);
    while (_undo.length > 50 || (chars > 2000000 && _undo.isNotEmpty)) {
      chars -= _undo.removeAt(0).text.length;
    }
  }

  EditorSnapshot? undo() {
    if (!canUndo) return null;
    _redo.add(current);
    current = _undo.removeLast();
    _lastTyping = 0;
    return current;
  }

  EditorSnapshot? redo() {
    if (!canRedo) return null;
    _undo.add(current);
    current = _redo.removeLast();
    _lastTyping = 0;
    return current;
  }
}

EditorSnapshot insertMarkup(EditorSnapshot raw, String markup) {
  final v = raw.asHtml();
  return EditorSnapshot(
    v.text.replaceRange(v.a, v.b, markup),
    v.a + markup.length,
    v.a + markup.length,
  );
}

EditorSnapshot wrapMarkup(
  EditorSnapshot raw,
  String before,
  String after, {
  String placeholder = '文字',
}) {
  final v = raw.asHtml(), selected = v.text.substring(v.a, v.b);
  if (v.a >= before.length &&
      v.text.substring(v.a - before.length, v.a) == before &&
      v.text.substring(v.b).startsWith(after)) {
    return EditorSnapshot(
      v.text.replaceRange(v.a - before.length, v.b + after.length, selected),
      v.a - before.length,
      v.b - before.length,
    );
  }
  final body = selected.isEmpty ? placeholder : selected;
  return EditorSnapshot(
    v.text.replaceRange(v.a, v.b, '$before$body$after'),
    v.a + before.length,
    v.a + before.length + body.length,
  );
}

EditorSnapshot listMarkup(EditorSnapshot raw, bool ordered) {
  final v = raw.asHtml(),
      body = v.text.substring(v.a, v.b),
      tag = ordered ? 'ol' : 'ul';
  final lines = body.isEmpty
      ? ['第一项', '第二项']
      : body.replaceAll('\r\n', '\n').split('\n');
  return insertMarkup(
    v,
    '<$tag>\n${lines.map((l) => '  <li>$l</li>').join('\n')}\n</$tag>',
  );
}

EditorSnapshot indentSource(EditorSnapshot v, bool outdent) {
  final from = v.a == 0 ? 0 : v.text.lastIndexOf('\n', v.a - 1) + 1;
  final to = v.b > v.a && v.text[v.b - 1] == '\n' ? v.b - 1 : v.b;
  final tail = v.text.indexOf('\n', to),
      until = tail < 0 ? v.text.length : tail;
  final original = v.text.substring(from, until), lines = original.split('\n');
  var delta = 0, firstDelta = 0;
  for (var i = 0; i < lines.length; i++) {
    final old = lines[i];
    lines[i] = outdent
        ? old.replaceFirst(RegExp(r'^(?:\t| {1,2})'), '')
        : '  $old';
    final n = lines[i].length - old.length;
    delta += n;
    if (i == 0) firstDelta = n;
  }
  final text = v.text.replaceRange(from, until, lines.join('\n'));
  return EditorSnapshot(
    text,
    (v.a + firstDelta).clamp(from, text.length),
    (v.b + delta).clamp(from, text.length),
    html: v.html,
  );
}

EditorSnapshot removeSelectionFormat(EditorSnapshot v) {
  if (v.a == v.b || !v.html) return v;
  // Clearing text formatting must not delete selected images, website cards,
  // table content or unknown components. Only known inline formatting wrappers
  // are removed; block structure and all embedded source bytes are retained.
  final token = RegExp(
    r'''<!--[\s\S]*?-->|<(?:pre|code)\b[^>]*>[\s\S]*?</(?:pre|code)\s*>|\[(dlbox|iframe|collapse|poll|lottery)\b[^\]]*\][\s\S]*?\[/\1\]|<(?:[^<>"']|"[^"]*"|'[^']*')*>''',
    caseSensitive: false,
  );
  final inline = RegExp(
    r'^<(/?)(b|strong|i|em|u|s|del|strike|font|sup|sub|span)\b',
    caseSensitive: false,
  );
  final tagPattern = RegExp(r'^<(/?)([a-z][a-z0-9]*)\b', caseSensitive: false);
  List<({String tag, String opening})> activeAt(int position) {
    final stack = <({String tag, String opening})>[];
    for (final match in token.allMatches(v.text)) {
      if (match.end > position) break;
      final tag = tagPattern.firstMatch(match[0]!);
      if (tag == null ||
          match[0]!.contains(
            RegExp(r'</(?:pre|code)\s*>', caseSensitive: false),
          )) {
        continue;
      }
      final name = tag[2]!.toLowerCase();
      if (tag[1]!.isEmpty) {
        if (![
              'img',
              'br',
              'hr',
              'input',
              'source',
              'wbr',
              'meta',
              'link',
              'area',
              'embed',
              'param',
              'track',
              'col',
              'base',
            ].contains(name) &&
            !match[0]!.endsWith('/>')) {
          stack.add((tag: name, opening: match[0]!));
        }
      } else {
        final at = stack.lastIndexWhere((entry) => entry.tag == name);
        if (at >= 0) stack.removeRange(at, stack.length);
      }
    }
    // Do not split block structure to clear a style inherited outside a paragraph.
    final block = stack.lastIndexWhere(
      (entry) => [
        'p',
        'div',
        'li',
        'td',
        'th',
        'h1',
        'h2',
        'h3',
        'blockquote',
      ].contains(entry.tag),
    );
    final from = stack.indexWhere(
      (entry) => inline.hasMatch(entry.opening),
      block + 1,
    );
    return from < 0 ? [] : stack.sublist(from);
  }

  final before = activeAt(v.a), after = activeAt(v.b);
  final keepBefore = before.where((entry) => !inline.hasMatch(entry.opening));
  final keepAfter = after.where((entry) => !inline.hasMatch(entry.opening));
  // A link nested inside a style wrapper must close and reopen as well, so
  // clearing only part of its text never creates crossed HTML tags.
  final close =
      before.reversed.map((entry) => '</${entry.tag}>').join() +
      keepBefore.map((entry) => entry.opening).join();
  final reopen =
      keepAfter.toList().reversed.map((entry) => '</${entry.tag}>').join() +
      after.map((entry) => entry.opening).join();
  final selected = v.text
      .substring(v.a, v.b)
      .replaceAllMapped(
        token,
        (match) => inline.hasMatch(match[0]!) ? '' : match[0]!,
      );
  final replacement = '$close$selected$reopen';
  return EditorSnapshot(
    v.text.replaceRange(v.a, v.b, replacement),
    v.a + close.length,
    v.a + close.length + selected.length,
    html: v.html,
  );
}

String replaceEditorText(String source, String needle, String replacement) {
  if (needle.isEmpty) return source;
  var count = 0, offset = 0;
  while (true) {
    final at = source.indexOf(needle, offset);
    if (at < 0) break;
    count++;
    offset = at + needle.length;
  }
  if (source.length + count * (replacement.length - needle.length) > 1000000) {
    throw const FormatException('替换结果超过100万字符，请缩小范围');
  }
  return source.replaceAll(needle, replacement);
}
