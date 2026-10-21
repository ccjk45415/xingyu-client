import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:xingyu_desktop/app.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/editor_hints.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/qr.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/ui/shared.dart';

import 'widget_test.dart'
    show FakeSite, FakeService, OfflineSocket, frames, capture;

Uint8List fixture(String name) => File(
  '${Directory.current.resolveSymbolicLinksSync()}/../tests/fixtures/$name',
).readAsBytesSync();

class SearchFixture extends FakeSite {
  Map<String, dynamic>? requested;
  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) async {
    if (path == 'user/list') {
      requested = params;
      return {
        'code': 0,
        'data': [
          {'id': 77, 'nickname': '测试作者', 'avatar': '', 'post_count': 9},
        ],
        'meta': {
          'pagination': {'total_pages': 2},
        },
      };
    }
    return super.get(path, params);
  }
}

void main() {
  setUpAll(() async {
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      await (FontLoader(
        'Microsoft YaHei UI',
      )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
    }
    final icons = File(
      'C:/codex-tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    );
    final codeFont = File('C:/Windows/Fonts/consola.ttf');
    if (codeFont.existsSync()) {
      await (FontLoader(
        'Consolas',
      )..addFont(codeFont.readAsBytes().then(ByteData.sublistView))).load();
    }
    if (icons.existsSync()) {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(icons.readAsBytes().then(ByteData.sublistView))).load();
    }
  });
  test('offline QR decodes Java generated UTF8 fixtures, rotated/inverted JPEG/WebP and blank images', () {
    final data = fixture('qr-link.png'), image = img.decodePng(data)!;
    const link = 'https://example.com/download?a=1&b=2#qr';
    expect(decodeQr(data), link);
    expect(decodeQr(fixture('qr-cjk.png')), 'https://example.com/资源?名称=星屿');
    expect(
      decodeQr(
        Uint8List.fromList(
          img.encodeJpg(img.copyRotate(image, angle: 90), quality: 85),
        ),
      ),
      link,
    );
    expect(
      decodeQr(Uint8List.fromList(img.encodePng(img.invert(image)))),
      link,
    );
    expect(decodeQr(img.encodeWebP(img.decodePng(data)!)), link);
    expect(
      decodeQr(
        Uint8List.fromList(img.encodePng(img.Image(width: 100, height: 100))),
      ),
      isNull,
    );
    expect(
      () => decodeQr(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
  test('code blocks escape C++/HTML while preserving whitespace and selected language', () {
    const source =
        '#include <iostream>\nint main() {\n  std::cout << "A & B";\n}';
    final html = codeBlock('cpp', source);
    expect(html, contains('class="language-cpp"'));
    expect(html, contains('&lt;iostream&gt;'));
    expect(html, contains('&amp;'));
    expect(html, contains('\n  std'));
    expect(html, isNot(contains('<iostream>')));
    expect(
      codeBlock('html', '<script>alert(1)</script>'),
      contains('&lt;script&gt;'),
    );
    expect(() => codeBlock('cpp" onclick="bad', source), throwsArgumentError);
    expect(htmlHints.length, 15);
    expect(codeLanguages.length, 17);
  });
  testWidgets(
    'right-click recognises QR locally and waits for explicit copy or open',
    (tester) async {
      final bytes = fixture('qr-link.png');
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: QrImageActions(
                bytes: bytes,
                child: Image.memory(
                  bytes,
                  width: 320,
                  height: 320,
                  key: const Key('qr.fixture'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('qr.fixture')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('识别二维码链接'), findsOneWidget);
      await tester.tap(find.text('识别二维码链接'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      await tester.pumpAndSettle();
      expect(find.text('二维码识别结果'), findsOneWidget);
      expect(find.text('打开链接'), findsOneWidget);
      expect(copied, isNull);
      await tester.tap(find.text('复制内容'));
      await tester.pump();
      expect(copied, 'https://example.com/download?a=1&b=2#qr');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'QR inside enlarged viewer can explicitly open an internal article',
    (tester) async {
      SecureVault.setMockInitialValues({});
      final app = AppState(
        siteApi: FakeSite(),
        serviceApi: FakeService(),
        socketFactory: OfflineSocket.new,
      )..starting = false;
      DeskRoute? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: DeskScope(
            app: app,
            open: (r) => opened = r,
            child: Scaffold(
              body: Builder(
                builder: (c) => TextButton(
                  onPressed: () =>
                      showImage(c, bytes: fixture('qr-internal.png')),
                  child: const Text('查看二维码'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('查看二维码'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byType(Image).first,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('识别二维码链接'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      await tester.pumpAndSettle();
      expect(opened, isNull);
      await tester.tap(find.text('打开链接'));
      await tester.pumpAndSettle();
      expect(opened?.kind, 'article');
      expect(opened?.id, 123);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
  testWidgets(
    'author search and HTML/code insertion work without posting to website',
    (tester) async {
      SecureVault.setMockInitialValues({});
      final site = SearchFixture();
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
          child: XingyuApp(app: app),
        ),
      );
      await frames(tester);
      final scope = tester.widget<DeskScope>(find.byType(DeskScope));
      scope.open(
        const DeskRoute('search', '搜索', query: '测试', filter: 'authors'),
      );
      await frames(tester);
      expect(find.text('测试作者'), findsOneWidget);
      expect(find.text('UID 77 · 9 篇投稿'), findsOneWidget);
      expect(site.requested?['search'], '测试');
      expect(tester.takeException(), isNull, reason: 'author search layout');
      await capture(tester, key, 'desktop-author-search');
      await tester.tap(find.text('下一页'));
      await frames(tester);
      expect(site.requested?['page'], 2);
      await tester.tap(find.text('测试作者'));
      await frames(tester);
      expect(find.text('作者主页'), findsWidgets);
      expect(tester.takeException(), isNull, reason: 'author page layout');
      scope.open(const DeskRoute('editor', '新建投稿'));
      await frames(tester);
      expect(tester.takeException(), isNull, reason: 'editor layout');
      await tester.tap(find.text('HTML 提示'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'HTML hints layout');
      await capture(tester, key, 'desktop-html-hints');
      expect(find.text('段落与换行'), findsOneWidget);
      await tester.tap(find.text('插入').first);
      await frames(tester);
      expect(tester.takeException(), isNull, reason: 'Inserted HTML preview');
      final input = tester.widget<TextField>(
        find.byKey(const Key('editor.content')),
      );
      expect(input.controller!.text, contains('<p>第一段文字</p>'));
      await tester.tap(find.text('插入代码块'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Code dialog layout');
      await tester.enterText(
        find.byKey(const Key('editor.code')),
        '#include <iostream>\nint main() { return 0; }',
      );
      await tester.pump();
      await capture(tester, key, 'desktop-code-dialog');
      await tester.tap(find.text('插入'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await frames(tester);
      expect(input.controller!.text, contains('language-cpp'));
      expect(input.controller!.text, contains('&lt;iostream&gt;'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      await tester.pump(const Duration(seconds: 2));
    },
  );
}
