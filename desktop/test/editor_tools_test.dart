import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/editor_tools.dart';

void main() {
  test('selected CJK text maps safely through plain HTML conversion and toggles formatting', () {
    final value = wrapMarkup(
      const EditorSnapshot('A & 星屿\nB', 4, 6, html: false),
      '<strong>',
      '</strong>',
    );
    expect(value.text, '<p>A &amp; <strong>星屿</strong><br>B</p>');
    expect(value.text.substring(value.a, value.b), '星屿');
    expect(
      wrapMarkup(value, '<strong>', '</strong>').text,
      '<p>A &amp; 星屿<br>B</p>',
    );
    final empty = wrapMarkup(
      const EditorSnapshot('', 0, 0),
      '<h2>',
      '</h2>',
      placeholder: '标题',
    );
    expect(empty.text.substring(empty.a, empty.b), '标题');
    expect(
      wrapMarkup(const EditorSnapshot('abcd', 3, 1), '<u>', '</u>').text,
      'a<u>bc</u>d',
    );
  });
  test('lists, indentation and clear-format preserve selected content and line boundaries', () {
    expect(
      listMarkup(const EditorSnapshot('一\n二', 0, 3), true).text,
      '<ol>\n  <li>一</li>\n  <li>二</li>\n</ol>',
    );
    const value = EditorSnapshot('first\n  second\nthird', 0, 15, html: false);
    final next = indentSource(value, false);
    expect(next.text, '  first\n    second\nthird');
    expect(indentSource(next, true).text, value.text);
    const marked = EditorSnapshot('<b>星屿 &amp; 文字</b>', 0, 18);
    expect(removeSelectionFormat(marked).text, '星屿 &amp; 文字');
    expect(
      removeSelectionFormat(const EditorSnapshot('a < b', 0, 5, html: false))
          .text,
      'a < b',
    );
  });
  test('literal replacement is bounded before allocation and undo is coalesced and reversible', () {
    expect(replaceEditorText(r'a$a$a', r'a$', r'b\$'), r'b\$b\$a');
    expect(replaceEditorText('aaa', 'aa', 'x'), 'xa');
    expect(
      () => replaceEditorText('a' * 1000, 'a', 'b' * 2000),
      throwsFormatException,
    );
    final h = EditorHistory(const EditorSnapshot('', 0, 0, html: false));
    h.record(
      const EditorSnapshot('a', 1, 1, html: false),
      typing: true,
      now: 1000,
    );
    h.record(
      const EditorSnapshot('ab', 2, 2, html: false),
      typing: true,
      now: 1100,
    );
    expect(h.undo()?.text, '');
    expect(h.redo()?.text, 'ab');
    h.record(wrapMarkup(h.current, '<em>', '</em>'), now: 1200);
    expect(h.undo()?.html, false);
    expect(h.redo()?.html, true);
    h.undo();
    h.record(const EditorSnapshot('changed', 7, 7));
    expect(h.canRedo, false);
    for (var i = 0; i < 80; i++) {
      h.record(EditorSnapshot('change$i', 0, 0));
    }
    var steps = 0;
    while (h.canUndo) {
      h.undo();
      steps++;
    }
    expect(steps, lessThanOrEqualTo(50));
  });
}
