import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/editor_links.dart';
import 'package:xingyu_desktop/core/visual_editor.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/pages/authoring.dart';
import 'package:xingyu_desktop/ui/shared.dart';
import 'package:xingyu_desktop/ui/editor_ime_anchor.dart';

import 'widget_test.dart' show FakeSite, FakeService, OfflineSocket, frames;

void main() {
  test('link edits retain formatting, neighbors, attributes and entities', () {
    const source =
        '<p>前 <a class="keep" target="_blank" href="https://example.com/a?a=1&amp;b=2"><strong>原始 &amp; 链接</strong></a> 后</p>';
    final editor = VisualHtmlController()..load(source);
    final at = editor.sourceOffset(editor.text.indexOf('原始') + 1);
    final link = EditorLink.at(source, at, at)!;
    expect(link.url, 'https://example.com/a?a=1&b=2');
    expect(link.label, '原始 & 链接');
    final updated = link.update(
      source,
      link.label,
      'https://example.com/new?a=3&b=4',
    );
    expect(updated, contains('<strong>原始 &amp; 链接</strong>'));
    expect(updated, contains('class="keep" target="_blank"'));
    expect(updated, contains('new?a=3&amp;b=4'));
    expect(
      link.update(source, '新 <名字>', link.url),
      contains('新 &lt;名字&gt;</a>'),
    );
    expect(
      link.update(source, link.label, link.url, remove: true),
      '<p>前 <strong>原始 &amp; 链接</strong> 后</p>',
    );
    expect(EditorLink.at(source, 3, source.length), isNull);
    expect(
      EditorLink.at(
        '<pre><code>&lt;a href="x"&gt;示例&lt;/a&gt;</code></pre>',
        2,
        2,
      ),
      isNull,
    );
    expect(
      EditorLink.at(
        '<a href="https://example.com"><img src="https://example.com/x.png"></a>',
        30,
        30,
      ),
      isNull,
    );
    editor.dispose();
  });

  testWidgets('normal editor saves existing links, undoes and unlinks', (
    tester,
  ) async {
    SecureVault.setMockInitialValues({});
    final app =
        AppState(
            siteApi: FakeSite(),
            serviceApi: FakeService(),
            socketFactory: OfflineSocket.new,
          )
          ..starting = false
          ..user = Map.from(FakeSite.user);
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: DeskScope(
          app: app,
          open: (_) {},
          child: const Scaffold(body: PostEditor(DeskRoute('editor', '新建投稿'))),
        ),
      ),
    );
    await frames(tester);
    final field = find.byKey(const Key('editor.content'));
    final editor =
        tester.widget<TextField>(field).controller! as VisualHtmlController;
    editor.load(
      '<p>前<a target="_blank" href="https://example.com/old"><strong>原链接</strong></a>后</p>',
    );
    editor.value = editor.value.copyWith(
      text: editor.text.replaceFirst('前', '前文'),
    );
    editor.selection = TextSelection.collapsed(
      offset: editor.text.indexOf('原链接') + 1,
    );
    await frames(tester);
    Future<void> openLink() async {
      await tester.ensureVisible(find.byTooltip('编辑/插入链接'));
      await tester.tap(find.byTooltip('编辑/插入链接'));
      await frames(tester);
    }

    await openLink();
    expect(find.text('编辑链接'), findsOneWidget);
    final inputs = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(inputs.first).controller!.text, '原链接');
    expect(
      tester.widget<TextField>(inputs.last).controller!.text,
      'https://example.com/old',
    );
    await tester.enterText(inputs.last, 'https://example.com/new?a=1&b=2');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    await frames(tester);
    expect(editor.source, contains('<strong>原链接</strong>'));
    expect(editor.source, contains('new?a=1&amp;b=2'));
    expect(RegExp('<a ').allMatches(editor.source).length, 1);
    editor.selection = TextSelection.collapsed(
      offset: editor.text.indexOf('原链接') + 1,
    );
    await openLink();
    await tester.enterText(inputs.first, '修改文字');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    await frames(tester);
    expect(editor.text, '前文修改文字后');
    await tester.tap(find.byTooltip('撤销'));
    await frames(tester);
    expect(editor.text, '前文原链接后');
    editor.selection = TextSelection.collapsed(
      offset: editor.text.indexOf('原链接') + 1,
    );
    await openLink();
    await tester.tap(find.text('移除链接'));
    await tester.pumpAndSettle();
    await frames(tester);
    expect(editor.source, isNot(contains('<a ')));
    expect(editor.source, contains('<strong>原链接</strong>'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
    app.dispose();
  });

  for (final normal in [true, false]) {
    testWidgets(
      'IME anchor follows caret, composition, scrolling and resize ($normal)',
      (tester) async {
        const channel = MethodChannel('moe.cangku.xingyu/editor_ime');
        final calls = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        tester.view.physicalSize = const Size(1000, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final focus = FocusNode();
        final outer = ScrollController(), inner = ScrollController();
        final controller = normal
            ? (VisualHtmlController()
                ..load(List.generate(90, (i) => '<p>段落 $i 内容</p>').join()))
            : TextEditingController(
                text: List.generate(90, (i) => '段落 $i 内容').join('\n'),
              );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                controller: outer,
                child: Column(
                  children: [
                    const SizedBox(height: 180),
                    EditorImeAnchor(
                      focusNode: focus,
                      controller: controller,
                      child: TextField(
                        controller: controller,
                        focusNode: focus,
                        scrollController: inner,
                        minLines: 8,
                        maxLines: 8,
                      ),
                    ),
                    const SizedBox(height: 900),
                  ],
                ),
              ),
            ),
          ),
        );
        focus.requestFocus();
        await tester.pumpAndSettle();
        controller.selection = TextSelection.collapsed(
          offset: controller.text.indexOf('段落 70') + 4,
        );
        final editable = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        editable.bringIntoView(controller.selection.extent);
        await tester.pumpAndSettle();
        void checkAnchor() {
          final geometry =
              calls.lastWhere((call) => call.method == 'setCaret').arguments
                  as Map;
          final range = controller.value.composing;
          final position = range.isValid && !range.isCollapsed
              ? range.start
              : controller.selection.extentOffset;
          final render = editable.renderEditable;
          final local = render.getLocalRectForCaret(
            TextPosition(offset: position),
          );
          final expected = render.localToGlobal(local.topLeft);
          expect(geometry['x'], closeTo(expected.dx, .1));
          expect(geometry['y'], closeTo(expected.dy, .1));
          expect(expected.dy, inInclusiveRange(0, 800));
          expect(geometry.keys, unorderedEquals(['x', 'y', 'width', 'height']));
        }

        expect(inner.offset, greaterThan(0));
        checkAnchor();
        outer.jumpTo(80);
        await tester.pump();
        await tester.pump();
        checkAnchor();
        final at = controller.selection.extentOffset;
        controller.value = controller.value.copyWith(
          composing: TextRange(start: at - 2, end: at),
        );
        await tester.pump();
        await tester.pump();
        checkAnchor();
        expect(controller.value.composing, TextRange(start: at - 2, end: at));
        tester.view.physicalSize = const Size(1200, 900);
        await tester.pumpAndSettle();
        checkAnchor();
        focus.unfocus();
        await tester.pumpAndSettle();
        expect(calls.last.method, 'clearCaret');
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        focus.dispose();
        outer.dispose();
        inner.dispose();
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}
