import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:image/image.dart' as image;
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/comment_content.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/ui/comment_composer.dart';
import 'package:xingyu_desktop/ui/shared.dart';

import 'widget_test.dart' show FakeSite, FakeService, OfflineSocket;
import 'widget_test.dart' show capture;

class CommentUploadSite extends FakeSite {
  int uploads = 0;
  Uint8List? uploaded;
  Completer<Json>? pending;
  @override
  Future<Json> upload(
    String path,
    String field,
    Uint8List bytes, [
    Json fields = const {},
  ]) async {
    expect(path, 'upload/image');
    expect(field, 'image');
    expect(fields, isEmpty);
    uploads++;
    uploaded = bytes;
    return pending == null
        ? {
            'data': {'url': 'https://file.cangku.moe/images/synthetic.png'},
          }
        : pending!.future;
  }
}

void main() {
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
  test('website sticker tokens use valid one-based indexes and preserve unknown text', () {
    for (final group in siteStickerGroups) {
      for (final index in [1, group.count]) {
        final doc = html.parseFragment(
          renderCommentContent(group.token(index)),
        );
        expect(doc.querySelector('img')?.attributes['src'], group.url(index));
      }
    }
    expect(
      renderCommentContent('[new_paopao:0][new_paopao:67][qq:93][bad:1]'),
      contains('[new_paopao:0]'),
    );
    final qq = html
        .parseFragment(renderCommentContent('[qq:12]'))
        .querySelector('img')!;
    expect(qq.attributes['src'], endsWith('/qq/12.gif'));
    expect(qq.attributes['class'], 'xingyu-site-sticker');
  });
  test(
    'mixed bare image URLs render without rewriting HTML attributes and code',
    () {
      final doc = html.parseFragment(
        renderCommentContent(
          '前面 https://file.cangku.moe/images/one.webp?x=1&y=2，后面 '
          '<img src="https://file.cangku.moe/images/two.jpg" alt="[qq:1]">'
          '<code>[qq:1] https://example.com/x.png</code> [new_paopao:12] '
          'https://example.com/download?file=a.png',
        ),
      );
      expect(doc.querySelectorAll('img').length, 3);
      expect(
        doc.querySelectorAll('img').first.attributes['src'],
        'https://file.cangku.moe/images/one.webp?x=1&y=2',
      );
      expect(
        doc.querySelector('code')!.text,
        '[qq:1] https://example.com/x.png',
      );
      expect(doc.text, contains('，后面'));
      expect(doc.text, contains('https://example.com/download?file=a.png'));
      expect(doc.querySelectorAll('img')[1].attributes['alt'], '[qq:1]');
      final lines = html.parseFragment(
        renderCommentContent('第一行\n第二行\r\n[qq:1]'),
      );
      expect(lines.querySelectorAll('br').length, 2);
      expect(isCommentImageUrl('https://u:p@example.com/image.jpg'), false);
      expect(isCommentImageUrl('javascript:alert(1).png'), false);
    },
  );
  test(
    'comment image bounds validate actual bytes and preserve upload formats',
    () {
      final png = Uint8List.fromList(
        image.encodePng(image.Image(width: 3, height: 5)),
      );
      expect(() => validateCommentImage(png), returnsNormally);
      final exact = Uint8List(commentImageLimit)..setAll(0, png);
      expect(() => validateCommentImage(exact), returnsNormally);
      expect(
        () => validateCommentImage(Uint8List(commentImageLimit + 1)),
        throwsA(isA<ApiFailure>()),
      );
      expect(
        () => validateCommentImage(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<ApiFailure>()),
      );
      expect(uploadImageType(png), ('png', 'image/png'));
      expect(uploadImageType(Uint8List.fromList([71, 73, 70, 56, 57, 97])), (
        'gif',
        'image/gif',
      ));
      expect(
        uploadImageType(
          Uint8List.fromList([82, 73, 70, 70, 0, 0, 0, 0, 87, 69, 66, 80]),
        ),
        ('webp', 'image/webp'),
      );
    },
  );

  testWidgets(
    'real cached images keep stickers inline and article long images bounded, wide and narrow',
    (tester) async {
      SecureVault.setMockInitialValues({});
      final app =
          AppState(
              siteApi: FakeSite(),
              serviceApi: FakeService(),
              socketFactory: OfflineSocket.new,
            )
            ..starting = false
            ..user = Map.from(FakeSite.user);
      await tester.runAsync(() async {
        for (final (url, width, height) in [
          for (final group in siteStickerGroups)
            for (var index = 1; index <= group.count; index++)
              (group.url(index), 32, 32),
          ('https://file.cangku.moe/images/comment-demo.png', 600, 240),
          ('https://file.cangku.moe/images/comment-html.png', 600, 240),
          ('https://file.cangku.moe/images/long-demo.png', 600, 2400),
        ]) {
          final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
          canvas.drawColor(const Color(0xffe9defb), BlendMode.src);
          for (var y = 0; y < height; y += 80) {
            canvas.drawRect(
              Rect.fromLTWH(0, y.toDouble(), width.toDouble(), 40),
              Paint()..color = const Color(0xffc9b4ec),
            );
          }
          final picture = recorder.endRecording(),
              decoded = await picture.toImage(width, height);
          for (final headers in [
            const {'Referer': '$siteOrigin/'},
            {
              'Referer': '$siteOrigin/',
              'User-Agent': 'Mozilla/5.0 XingyuDesktop/$desktopVersion',
            },
          ]) {
            PaintingBinding.instance.imageCache.putIfAbsent(
              NetworkImage(url, headers: headers),
              () => OneFrameImageStreamCompleter(
                Future.value(ImageInfo(image: decoded.clone())),
              ),
            );
          }
          decoded.dispose();
          picture.dispose();
        }
      });
      tester.view.devicePixelRatio = 1;

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      for (final width in [1280.0, 430.0]) {
        await tester.pumpWidget(const SizedBox());
        tester.view.physicalSize = Size(width, 1100);
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: ThemeData(
                fontFamily: 'Microsoft YaHei UI',
                colorScheme: ColorScheme.fromSeed(seedColor: violet),
              ),
              home: DeskScope(
                app: app,
                open: (_) {},
                child: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(24),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '评论与图片 · 合成布局验证',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          RichContent(
                            renderCommentContent(
                              '前面的文字 [new_paopao:12] 后面的文字\nhttps://file.cangku.moe/images/comment-demo.png\n<img src="https://file.cangku.moe/images/comment-html.png">',
                            ),
                            fontSize: 15,
                            maxImageHeight: 220,
                            maxImageWidth: 480,
                          ),
                          const Text('作品详情长图（点击可查看原图）'),
                          const RichContent(
                            '<span class="text-forbidden"><img src="https://file.cangku.moe/images/long-demo.png"></span>',
                            fontSize: 15,
                            maxImageHeight: 520,
                            maxImageWidth: 760,
                          ),
                          const Text('后续正文'),
                          Builder(
                            builder: (c) => FilledButton(
                              onPressed: () => composeComment(c, '发表评论'),
                              child: const Text('写评论'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final sticker = find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is NetworkImage &&
              (w.image as NetworkImage).url == siteStickerGroups[1].url(12),
        );
        expect(tester.getSize(sticker), const Size(32, 32));
        expect(tester.getRect(sticker).left, greaterThan(80));
        await tester.tap(find.text('点击显示隐藏文字'));
        await tester.pumpAndSettle();
        final long = find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is NetworkImage &&
              (w.image as NetworkImage).url.endsWith('long-demo.png'),
        );
        expect(tester.getSize(long).height, lessThanOrEqualTo(520));
        expect(tester.getSize(long).width, lessThanOrEqualTo(760));
        expect(
          tester.getRect(find.text('后续正文')).top,
          greaterThanOrEqualTo(tester.getRect(long).bottom),
        );
        expect(find.text('[图片暂时无法加载]'), findsNothing);
        expect(find.text('[表情]'), findsNothing);
        await capture(tester, key, 'desktop-comment-media-${width.toInt()}');
        await tester.ensureVisible(find.text('写评论'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('写评论'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField),
          '前面的文字 [new_paopao:12] 后面的文字\nhttps://file.cangku.moe/images/comment-demo.png',
        );
        await tester.tap(find.text('官网表情'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('预览'));
        await tester.pumpAndSettle();
        expect(find.text('添加图片'), findsOneWidget);
        expect(find.text('粘贴'), findsOneWidget);
        expect(tester.takeException(), null);
        await capture(tester, key, 'desktop-comment-composer-${width.toInt()}');
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
  for (final mode in ['text', 'error', 'stale-session']) {
    testWidgets('clipboard $mode preserves plain text and scoped uploads', (
      tester,
    ) async {
      SecureVault.setMockInitialValues({});
      final site = CommentUploadSite();
      final app =
          AppState(
              siteApi: site,
              serviceApi: FakeService(),
              socketFactory: OfflineSocket.new,
            )
            ..starting = false
            ..user = Map.from(FakeSite.user);
      const channel = MethodChannel('moe.cangku.xingyu/image_clipboard');
      var textReads = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (mode == 'error') {
          throw PlatformException(
            code: 'clipboard_image',
            message: 'Image exceeds 1 MB',
          );
        }
        if (mode == 'stale-session') {
          app.site.generation++;
          return Uint8List.fromList(
            image.encodePng(image.Image(width: 2, height: 2)),
          );
        }
        return null;
      });
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          textReads++;
          return {'text': '纯文本粘贴'};
        }
        if (call.method == 'Clipboard.hasStrings') return {'value': false};
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: DeskScope(
            app: app,
            open: (_) {},
            child: Scaffold(
              body: Builder(
                builder: (c) => FilledButton(
                  onPressed: () => composeComment(c, '评论'),
                  child: const Text('开始'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('开始'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '原文');
      if (mode == 'text') {
        // Image-only clipboards still expose a paste command in the right-click menu.
        await tester.tap(
          find.byType(TextField),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();
        expect(find.text('粘贴图片或文字'), findsOneWidget);
        await tester.tap(find.text('粘贴图片或文字'));
      } else {
        await tester.tap(find.text('粘贴'));
      }
      await tester.pumpAndSettle();
      final value = tester
          .widget<TextField>(find.byType(TextField))
          .controller!
          .text;
      expect(site.uploads, 0);
      expect(value, mode == 'text' ? contains('纯文本粘贴') : '原文');
      expect(textReads, mode == 'text' ? 1 : 0);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    });
  }
  for (final changeOwner in [false, true]) {
    testWidgets(
      'real clipboard image intent uploads original bytes, account switch=$changeOwner',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 1000);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SecureVault.setMockInitialValues({});
        final site = CommentUploadSite();
        if (changeOwner) site.pending = Completer<Json>();
        final app =
            AppState(
                siteApi: site,
                serviceApi: FakeService(),
                socketFactory: OfflineSocket.new,
              )
              ..starting = false
              ..user = Map.from(FakeSite.user);
        final png = Uint8List.fromList(
          image.encodePng(image.Image(width: 3, height: 5)),
        );
        var reads = 0;
        const channel = MethodChannel('moe.cangku.xingyu/image_clipboard');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              expect(call.method, 'readImage');
              reads++;
              return png;
            });

        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        String? submitted;
        await tester.pumpWidget(
          MaterialApp(
            home: DeskScope(
              app: app,
              open: (_) {},
              child: Scaffold(
                body: Builder(
                  builder: (c) => FilledButton(
                    onPressed: () async {
                      submitted = await composeComment(c, '测试评论');
                    },
                    child: const Text('开始'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('开始'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '开始结束');
        final controller = tester
            .widget<TextField>(find.byType(TextField))
            .controller!;
        controller.selection = const TextSelection.collapsed(offset: 2);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(reads, 1);
        expect(site.uploads, 1);
        expect(site.uploaded, orderedEquals(png));
        if (changeOwner) {
          app.user = {...FakeSite.user, 'id': 999};
          site.pending!.complete({
            'data': {'url': 'https://file.cangku.moe/images/synthetic.png'},
          });
          await tester.pumpAndSettle();
          expect(controller.text, '开始结束');
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(submitted, null);
        } else {
          await tester.pumpAndSettle();
          expect(
            controller.text,
            '开始 https://file.cangku.moe/images/synthetic.png 结束',
          );
          await tester.tap(find.text('发布'));
          await tester.pumpAndSettle();
          expect(submitted, controller.text);
        }
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      },
    );
  }
}
