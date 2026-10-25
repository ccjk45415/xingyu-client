import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/editor_export.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/core/visual_editor.dart';
import 'package:xingyu_desktop/pages/authoring.dart';
import 'package:xingyu_desktop/ui/editor_templates.dart';
import 'package:xingyu_desktop/ui/shared.dart';

import 'widget_test.dart'
    show FakeSite, FakeService, OfflineSocket, frames, capture;

class UploadSite extends FakeSite {
  final uploading = Completer<Json>();
  bool called = false;
  @override
  Future<Json> upload(
    String path,
    String field,
    Uint8List bytes, [
    Json fields = const {},
  ]) {
    called = true;
    return uploading.future;
  }
}

void main() {
  test('shortcodes inside a code example stay editable literal text', () {
    const original = '<pre><code>[dlbox title="example"][/dlbox]</code></pre>';
    final editor = VisualHtmlController()..load(original);
    expect(editor.text, contains('[dlbox'));
    expect(editor.text, isNot(contains('\uFFFC')));
    expect(editor.source, original);
    editor.dispose();
  });
  setUpAll(() async {
    for (final (family, path) in [
      ('Microsoft YaHei UI', 'C:/Windows/Fonts/msyh.ttc'),
      (
        'MaterialIcons',
        'C:/codex-tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ),
    ]) {
      final file = File(path);
      if (file.existsSync()) {
        await (FontLoader(
          family,
        )..addFont(file.readAsBytes().then(ByteData.sublistView))).load();
      }
    }
  });
  test('IME, surrogate replacement, entities, Enter and explicit image deletion are lossless', () {
    final editor = VisualHtmlController()
      ..load(
        '<p data-x="1">日😀&NotEqualTilde;<img src="https://example.com/a.png">末</p>[iframe]https://example.com[/iframe]',
      );
    editor.value = TextEditingValue(
      text: editor.text.replaceFirst('日', '日本'),
      selection: const TextSelection.collapsed(offset: 2),
      composing: const TextRange(start: 0, end: 2),
    );
    expect(editor.value.composing, const TextRange(start: 0, end: 2));
    expect(editor.source, startsWith('<p data-x="1">日本😀&NotEqualTilde;'));
    editor.value = TextEditingValue(
      text: editor.text.replaceFirst('😀', '😁'),
      selection: const TextSelection.collapsed(offset: 4),
    );
    expect(editor.source, contains('日本😁&NotEqualTilde;'));
    final image = editor.text.indexOf('\uFFFC');
    editor.value = TextEditingValue(
      text: editor.text.replaceRange(image + 1, image + 1, '\n后续'),
      selection: TextSelection.collapsed(offset: image + 4),
    );
    expect(
      editor.source,
      contains('<img src="https://example.com/a.png"><br>后续末'),
    );
    editor.value = TextEditingValue(
      text: editor.text.replaceRange(image, image + 1, ''),
      selection: TextSelection.collapsed(offset: image),
    );
    expect(editor.source, isNot(contains('<img')));
    expect(editor.source, endsWith('[iframe]https://example.com[/iframe]'));
    editor.load('<p>&NotEqualTilde;</p>');
    editor.value = const TextEditingValue(
      text: '≂x',
      selection: TextSelection.collapsed(offset: 2),
    );
    expect(editor.text, '≂x');
    expect(editor.source, '<p>≂x</p>');
    var rejected = false;
    editor.onEditError = (_) => rejected = true;
    editor.value = TextEditingValue(
      text: '<' * 250001,
      selection: const TextSelection.collapsed(offset: 0),
    );
    expect(rejected, true);
    expect(editor.source, '<p>≂x</p>');
    editor.dispose();
  });
  test('native projection edits text without rewriting source, images or unknown components', () {
    const raw =
        '<!--keep--><p data-extra="yes"><b>星屿 &amp; 😀</b>'
        '<img src="https://example.com/a.png" alt="图" style="width:77%">'
        '<span style="color:#f0c">正文</span></p>'
        '[dlbox title="原始卡片" link1="盘|https://example.com"][/dlbox]'
        '<custom-widget abc="1">未知组件</custom-widget>';
    final editor = VisualHtmlController()..load(raw);
    expect(editor.text, contains('星屿 & 😀'));
    expect(editor.source, raw);
    final pos = editor.text.indexOf('正文');
    editor.value = TextEditingValue(
      text: editor.text.replaceRange(pos, pos + 2, '新的介绍'),
      selection: TextSelection.collapsed(offset: pos + 4),
    );
    expect(editor.source, raw.replaceFirst('正文', '新的介绍'));
    final changed = editor.source;
    editor.load(changed);
    expect(editor.source, changed);
    expect(editor.text, isNot(contains('<p')));
    editor.dispose();
  });
  test('plain typing escapes HTML and preserves styles across deletion and paragraphs', () {
    final editor = VisualHtmlController()..load('<p><b>加粗</b>普通</p><p>第二段</p>');
    expect(editor.text, '加粗普通\n第二段');
    editor.value = TextEditingValue(
      text: editor.text.replaceRange(1, 3, '<新增&>'),
      selection: const TextSelection.collapsed(offset: 6),
    );
    expect(editor.source, contains('<b>加&lt;新增&amp;&gt;</b>通'));
    expect(editor.source, contains('<p>第二段</p>'));
    editor.load('<p>一</p><p>二</p>');
    editor.value = const TextEditingValue(
      text: '一二',
      selection: TextSelection.collapsed(offset: 1),
    );
    expect(editor.source, '<p>一二</p>');
    editor.dispose();
  });
  test('website templates have official field contract, rapid encoding and safe validation', () {
    final raw = downloadTemplate(
      title: '软件',
      time: '2026-10-21',
      source: '作者',
      code: '1234',
      password: 'xyz',
      links: [
        (name: '下载一', url: 'https://example.com/a'),
        (name: '下载二', url: 'https://example.com/b'),
      ],
    );
    expect(
      raw,
      '[dlbox title="软件" time="2026-10-21" info="提取：1234 / 密码：xyz" from="作者" link1="下载一|https://example.com/a" link2="下载二|https://example.com/b"][/dlbox]',
    );
    expect(
      externalTemplate('https://www.youtube.com/watch?v=abc'),
      '[iframe]https://www.youtube.com/watch?v=abc[/iframe]',
    );
    expect(
      () => externalTemplate('javascript:alert(1)'),
      throwsFormatException,
    );
    expect(
      () => externalTemplate('https://example.com/[iframe]'),
      throwsFormatException,
    );
    expect(
      rapidDownloadLink('abc\n中文', false),
      'https://pan.baidu.com/#bdlink=YWJjCuS4reaWhw==',
    );
    final ali = rapidDownloadLink('aliyunpan://abc中文', true);
    expect(ali, startsWith('https://www.aliyundrive.com/drive/#alink='));
    expect(
      utf8.decode(base64Decode(ali.split('#alink=').last)),
      'aliyunpan://abc中文',
    );
  });
  test('print export retains safe pictures and resources but never script or network execution', () {
    final html = printablePost(
      '<标题>',
      '<p onclick="alert(1)">介绍</p><img src="https://example.com/a.png" onerror="alert(2)"><img src="file:///secret"><script>alert(3)</script><iframe src="https://evil.example"></iframe><a href="javascript:alert(4)">链接</a><span style="color:red;background:url(https://evil.example);font-size:20px">文字</span>[dlbox title="示例" link1="下载|https://example.com/a"][/dlbox]',
    );
    expect(html, contains('&lt;标题&gt;'));
    expect(html, contains('https://example.com/a.png'));
    expect(html, contains('default-src \'none\''));
    expect(html, isNot(contains('<script')));
    expect(html, isNot(contains('onclick')));
    expect(html, isNot(contains('onerror')));
    expect(html, isNot(contains('javascript:')));
    expect(html, isNot(contains('file:///secret')));
    expect(html, isNot(contains('background:url')));
    expect(html, contains('font-size:20px'));
    expect(html, contains('https://example.com/a'));
  });
  testWidgets(
    'existing website cards retain arbitrary info, all links, custom attributes and URL queries',
    (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () async {
                  result = await showDownloadTemplateDialog(
                    c,
                    initialMarkup: '[dlbox title="原有下载" time="2026-10-21" from="原有来源" info="文件大小：1GB" custom="keep" link1="一|https://example.com/a?a=1&amp;b=2" link23="二十三|https://example.com/23"][/dlbox]',
                  );
                },
                child: const Text('打开卡片'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开卡片'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, '原有文件信息（留空后使用上方提取码与解压码）'),
            )
            .controller!
            .text,
        '文件大小：1GB',
      );
      expect(find.widgetWithText(TextField, '名称'), findsNWidgets(2));
      await tester.tap(find.text('插入'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      expect(result, contains('info="文件大小：1GB"'));
      expect(result, contains('custom="keep"'));
      expect(result, contains('https://example.com/23'));
      expect(result, contains('https://example.com/a?a=1&amp;b=2'));
      expect(
        externalTemplate('https://example.com/watch?a=1&b=2'),
        '[iframe]https://example.com/watch?a=1&b=2[/iframe]',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'visual source roundtrip, busy image upload and independent wheel preview',
    (tester) async {
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 600, 220),
          Paint()..color = const Color(0xffece2ff),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(24, 22, 552, 176),
            const Radius.circular(20),
          ),
          Paint()..color = Colors.white,
        );
        canvas.drawCircle(const Offset(72, 83), 22, Paint()..color = violet);
        final heading = TextPainter(
          text: const TextSpan(
            text: '星屿创作 · 合成插图',
            style: TextStyle(
              fontFamily: 'Microsoft YaHei UI',
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xff45345d),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 450);
        heading.paint(canvas, const Offset(110, 60));
        final note = TextPainter(
          text: const TextSpan(
            text: '直接输入 · 原生排版 · 图片随正文保存',
            style: TextStyle(
              fontFamily: 'Microsoft YaHei UI',
              fontSize: 18,
              color: Color(0xff80718e),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 470);
        note.paint(canvas, const Offset(56, 125));
        final picture = recorder.endRecording();
        final image = await picture.toImage(600, 220);
        for (final headers in [
          const {'Referer': 'https://cangku.moe/'},
          {
            'Referer': 'https://cangku.moe/',
            'User-Agent': 'Mozilla/5.0 XingyuDesktop/$desktopVersion',
          },
        ]) {
          PaintingBinding.instance.imageCache.putIfAbsent(
            NetworkImage(
              'https://file.cangku.moe/images/synthetic-test.webp',
              headers: headers,
            ),
            () => OneFrameImageStreamCompleter(
              Future.value(ImageInfo(image: image.clone())),
            ),
          );
        }
        image.dispose();
        picture.dispose();
        heading.dispose();
        note.dispose();
      });
      SecureVault.setMockInitialValues({});
      final site = UploadSite();
      final app =
          AppState(
              siteApi: site,
              serviceApi: FakeService(),
              socketFactory: OfflineSocket.new,
            )
            ..starting = false
            ..user = Map.from(FakeSite.user);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: 'Microsoft YaHei UI',
              colorScheme: ColorScheme.fromSeed(seedColor: violet),
            ),
            home: DeskScope(
              app: app,
              open: (_) {},
              child: Scaffold(
                body: PostEditor(
                  const DeskRoute('editor', '新建投稿'),
                  imagePicker: (_) async => Uint8List.fromList([1, 2, 3]),
                ),
              ),
            ),
          ),
        ),
      );
      await frames(tester);
      final field = find.byKey(const Key('editor.content'));
      expect(
        tester.widget<TextField>(field).controller,
        isA<VisualHtmlController>(),
      );
      await tester.enterText(field, '开始结束');
      final input = tester.widget<TextField>(field).controller!;
      input.selection = const TextSelection.collapsed(offset: 2);
      await tester.ensureVisible(find.byTooltip('上传正文图片'));
      await tester.tap(find.byTooltip('上传正文图片'));
      await frames(tester);
      expect(site.called, true);
      expect(tester.widget<TextField>(field).enabled, false);
      site.uploading.complete({
        'code': 0,
        'data': {'url': 'https://file.cangku.moe/images/synthetic-test.webp'},
      });
      await frames(tester);
      final visual =
          tester.widget<TextField>(field).controller! as VisualHtmlController;
      expect(
        visual.source,
        '开始<img src="https:&#47;&#47;file.cangku.moe&#47;images&#47;synthetic-test.webp" alt="图片">结束',
      );
      expect(visual.text, '开始\uFFFC结束');
      await tester.tap(find.text('HTML源码'));
      await frames(tester);
      final source = tester.widget<TextField>(field).controller!;
      expect(source.text, visual.source);
      final long =
          '<h2>合成功能演示</h2><p><strong>不用代码也能发图</strong></p>'
          '<img src="https://file.cangku.moe/images/synthetic-test.webp" alt="图片">'
          '${List.generate(70, (i) => '<p>预览段落 $i：独立滚动测试</p>').join()}<p>最后一段</p>';
      source.value = TextEditingValue(
        text: long,
        selection: const TextSelection.collapsed(offset: 0),
      );
      await frames(tester);
      await tester.ensureVisible(
        find.byKey(const Key('editor.preview.scroll')),
      );
      await tester.pumpAndSettle();
      final scroll = find.byKey(const Key('editor.preview.scroll'));
      final titleLocation = tester.getTopLeft(find.text('HTML源码'));
      final state = tester.state<ScrollableState>(
        find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
      );
      final first = state.position.pixels;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(scroll),
          scrollDelta: const Offset(0, 100000),
        ),
      );
      await frames(tester);
      expect(state.position.pixels, greaterThan(first));
      expect(state.position.pixels, closeTo(state.position.maxScrollExtent, 1));
      expect(tester.getTopLeft(find.text('HTML源码')), titleLocation);
      expect(source.text, long);
      await capture(tester, key, 'desktop-editor-preview-scrollbar');
      const example =
          '<h2>像写文章一样轻松投稿</h2><p><strong>不用写代码，也能排版和发图片。</strong></p><p>直接输入介绍，再用工具栏添加正文图片、下载卡片和外部链接。</p><p><img src="https://file.cangku.moe/images/synthetic-test.webp" alt="合成二维码示例"></p>[dlbox title="星屿客户端下载示例" time="2026-10-21" from="开源项目" info="提取：1234 / 密码：example" link1="示例下载|https://example.com/download"][/dlbox]';
      source.value = const TextEditingValue(
        text: example,
        selection: TextSelection.collapsed(offset: 0),
      );
      await frames(tester);
      await tester.ensureVisible(find.text('HTML源码'));
      await tester.tap(find.text('HTML源码'));
      await frames(tester);
      expect(
        (tester.widget<TextField>(field).controller! as VisualHtmlController)
            .source,
        example,
      );
      final preview = tester
          .widget<SingleChildScrollView>(
            find.byKey(const Key('editor.preview.scroll')),
          )
          .controller!;
      preview.jumpTo(0);
      await frames(tester);
      final debugEditable = tester
          .state<EditableTextState>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .renderEditable;
      final bodyImageAt = visual.text.indexOf('\uFFFC');
      final imageBox = debugEditable
          .getBoxesForSelection(
            TextSelection(
              baseOffset: bodyImageAt,
              extentOffset: bodyImageAt + 1,
            ),
          )
          .first;
      final textBox = debugEditable
          .getBoxesForSelection(
            TextSelection(
              baseOffset: bodyImageAt - 2,
              extentOffset: bodyImageAt - 1,
            ),
          )
          .first;
      final cardAt = visual.text.lastIndexOf('\uFFFC');
      final cardBox = debugEditable
          .getBoxesForSelection(
            TextSelection(baseOffset: cardAt, extentOffset: cardAt + 1),
          )
          .first;
      final imageRect = tester.getRect(
        find.descendant(of: field, matching: find.byType(Image)).first,
      );
      expect(
        imageRect.top,
        greaterThanOrEqualTo(
          debugEditable.localToGlobal(Offset(0, textBox.bottom)).dy,
        ),
      );
      final cardRect = tester.getRect(find.text('下载链接卡片'));
      expect(cardRect.top, greaterThanOrEqualTo(imageRect.bottom));
      expect(imageBox.bottom - imageBox.top, greaterThan(170));
      expect(cardBox.bottom, greaterThan(imageBox.bottom));
      expect(find.text('图片暂时无法加载 · 地址已保留'), findsNothing);
      expect(find.text('[图片暂时无法加载]'), findsNothing);
      await capture(tester, key, 'desktop-editor-native-visual');
      await tester.tap(
        find.descendant(of: field, matching: find.byType(Image)).first,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('全部图片设置'), findsOneWidget);
      await tester.tap(find.text('全部图片设置'));
      await tester.pumpAndSettle();
      expect(find.text('图片设置'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, '图片说明'), '合成插图已编辑');
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(visual.source, contains('合成插图已编辑'));
      await tester.tap(find.text('下载链接卡片'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '下载链接标题'))
            .controller!
            .text,
        '星屿客户端下载示例',
      );
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '上传时间'))
            .controller!
            .text,
        '2026-10-21',
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      final beforeFocus = visual.source;
      await tester.ensureVisible(find.byTooltip('专注编辑'));
      await tester.tap(find.byTooltip('专注编辑'));
      await frames(tester);
      expect(find.text('一个吸引人的标题…'), findsNothing);
      expect(
        identical(tester.widget<TextField>(field).controller, visual),
        true,
      );
      await tester.tap(find.byTooltip('全选正文'));
      await frames(tester);
      expect(
        visual.selection,
        TextSelection(baseOffset: 0, extentOffset: visual.text.length),
      );
      expect(visual.source, beforeFocus);
      await tester.tap(find.byTooltip('退出专注编辑'));
      await frames(tester);
      expect(visual.source, beforeFocus);
      await tester.ensureVisible(find.byTooltip('插入下载卡片模板'));
      await tester.tap(find.byTooltip('插入下载卡片模板'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '下载链接标题'),
        '开源客户端下载',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '上传时间'),
        '2026-10-21',
      );
      await tester.enterText(find.widgetWithText(TextField, '文件来源'), '开源项目');
      await tester.enterText(find.widgetWithText(TextField, '提取码'), '1234');
      await tester.enterText(find.widgetWithText(TextField, '解压码'), 'example');
      await tester.enterText(
        find.widgetWithText(TextField, '名称'),
        '官方 Release',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '链接'),
        'https://example.com/download',
      );
      await tester.pumpAndSettle();
      await capture(tester, key, 'desktop-editor-download-dialog');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.byTooltip('插入外部链接'));
      await tester.tap(find.byTooltip('插入外部链接'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('editor.external.url')),
        'https://www.youtube.com/watch?v=example',
      );
      await capture(tester, key, 'desktop-editor-external-dialog');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.byTooltip('撤销'));
      await tester.tap(find.byTooltip('撤销'));
      await frames(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      await tester.pump(const Duration(seconds: 2));
    },
  );
}
