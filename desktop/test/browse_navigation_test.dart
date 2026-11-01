import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/browse_cache.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/pages/discovery.dart';
import 'package:xingyu_desktop/ui/browse_pagination.dart';
import 'package:xingyu_desktop/ui/category_tab_strip.dart';
import 'package:xingyu_desktop/ui/shared.dart';

Json pageResult(int total) => {
  'meta': {
    'pagination': {'total_pages': total},
  },
};

class ManyCategoriesSite extends SiteApi {
  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) async {
    if (path == 'category/list') {
      return {
        'data': List.generate(
          14,
          (i) => {
            'id': 100 + i,
            'name': '兴趣分类 $i',
            'children': List.generate(
              14,
              (j) => {'id': 1000 + i * 100 + j, 'name': '作品子分类 $j'},
            ),
          },
        ),
      };
    }
    return {
      'data': [
        {
          'id': 1,
          'title': '作品预览 · 新的故事正在这里发生',
          'thumb': '',
          'user': {'id': 47, 'nickname': '测试作者'},
          'categories': [],
          'view_count': 98,
          'created_at': '2026-11-01T00:00:00Z',
        },
      ],
      ...pageResult(20),
    };
  }
}

Future<void> captureCategory(
  WidgetTester tester,
  GlobalKey key,
  int width,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/category-compact-$width.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
  });
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
      if (File(path).existsSync()) {
        await (FontLoader(
          family,
        )..addFont(File(path).readAsBytes().then(ByteData.sublistView))).load();
      }
    }
  });
  setUp(() async {
    SecureVault.setMockInitialValues({});
    BrowseCache.shared.directory = null;
    await BrowseCache.shared.clear();
  });

  test('unknown and empty page counts remain a single page', () {
    expect(browsePageCount({}), 1);
    expect(browsePageCount(pageResult(0)), 1);
    expect(browsePageCount(pageResult(31)), 31);
  });

  for (final width in [280.0, 390.0, 1080.0]) {
    testWidgets('page jump is usable and bounded at $width pixels', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final changed = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrowsePagination(pageResult(20), 3, changed.add),
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('browse.page.input')), '21');
      await tester.tap(find.byKey(const Key('browse.page.jump')));
      await tester.pump();
      expect(changed, isEmpty);
      expect(find.text('请输入 1–20 页'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('browse.page.input')), '0');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pump();
      expect(changed, isEmpty);

      await tester.enterText(find.byKey(const Key('browse.page.input')), '17');
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pump();
      expect(changed, [17]);
      expect(find.text('请输入 1–20 页'), findsNothing);
      await tester.tap(find.byKey(const Key('browse.page.previous')));
      await tester.tap(find.byKey(const Key('browse.page.next')));
      expect(changed, [17, 2, 4]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('changing the current page resets the jump input', (
    tester,
  ) async {
    Widget pager(int page) => MaterialApp(
      home: Scaffold(body: BrowsePagination(pageResult(20), page, (_) {})),
    );
    await tester.pumpWidget(pager(1));
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('browse.page.previous')))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('browse.page.input')), '8');
    await tester.pumpWidget(pager(20));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('browse.page.input')))
          .controller!
          .text,
      '20',
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('browse.page.next')))
          .onPressed,
      isNull,
    );
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets('category navigation stays compact and scrollable at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppState(siteApi: ManyCategoriesSite())
        ..starting = false
        ..user = {'id': 47, 'nickname': '测试作者'};
      final shot = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Microsoft YaHei UI',
            colorSchemeSeed: violet,
          ),
          home: DeskScope(
            app: app,
            open: (_) {},
            child: RepaintBoundary(
              key: shot,
              child: const Scaffold(body: CategoryTabsPage()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await captureCategory(tester, shot, width.toInt());
      expect(
        tester.getSize(find.byKey(const Key('category.compact-header'))).height,
        lessThanOrEqualTo(54),
      );
      final strips = find.byType(CategoryTabStrip);
      expect(strips, findsNWidgets(2));
      for (var i = 0; i < 2; i++) {
        final scrollbar = tester.widget<Scrollbar>(
          find.descendant(of: strips.at(i), matching: find.byType(Scrollbar)),
        );
        expect(scrollbar.thumbVisibility, true);
        expect(scrollbar.interactive, true);
        expect(scrollbar.controller!.position.maxScrollExtent, greaterThan(0));
        scrollbar.controller!.jumpTo(
          scrollbar.controller!.position.maxScrollExtent,
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('兴趣分类 13').hitTestable(), findsOneWidget);
      expect(find.text('作品子分类 13').hitTestable(), findsOneWidget);
      await tester.tap(find.text('作品子分类 13').hitTestable());
      await tester.pumpAndSettle();
      expect(
        object(object(app.local['categoryCursor'])['47'])['selected'],
        1013,
      );
      await tester.ensureVisible(find.byKey(const Key('browse.page.input')));
      await tester.enterText(find.byKey(const Key('browse.page.input')), '2');
      await tester.tap(find.byKey(const Key('browse.page.jump')));
      await tester.pumpAndSettle();
      expect(object(object(app.local['categoryCursor'])['47'])['page'], 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    });
  }
}
