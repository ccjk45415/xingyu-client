import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/app.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/pages/reading.dart';
import 'package:xingyu_desktop/ui/shared.dart';

import 'widget_test.dart' show FakeSite, FakeService, OfflineSocket, capture;

class ThreadSite extends FakeSite {
  final reads = <(String, Map<String, dynamic>)>[], writes = <(String, Json)>[];
  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) async {
    reads.add((path, {...?params}));
    if (path == 'comment/list') {
      final page = number(params?['page']);
      return {
        'data': [
          for (int i = 0; i < 4; i++)
            {
              'id': 100 + page * 10 + i,
              'post_id': 7,
              'parent_id': 21,
              'user_id': 77,
              'user': {'id': 77, 'nickname': '讨论作者'},
              'content': '第$page页回复 $i：这是一段用于布局和交互检查的合成回复。',
              'created_at': '2026-10-23T02:00:00Z',
              'vote_count': 2,
              'children': {'data': []},
            },
        ],
        'meta': {
          'pagination': {'current_page': page, 'total_pages': 2, 'total': 8},
        },
      };
    }
    if (path == 'user/followableIdList') {
      return {
        'data': [110],
      };
    }
    return super.get(path, params);
  }

  @override
  Future<Json> post(String path, Json body) async {
    writes.add((path, body));
    return {'data': {}};
  }
}

void main() {
  setUpAll(() async {
    for (final entry in [
      ('Microsoft YaHei UI', 'C:/Windows/Fonts/msyh.ttc'),
      (
        'MaterialIcons',
        'C:/codex-tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ),
    ]) {
      final file = File(entry.$2);
      if (await file.exists()) {
        await (FontLoader(
          entry.$1,
        )..addFont(file.readAsBytes().then(ByteData.sublistView))).load();
      }
    }
  });
  setUp(() => SecureVault.setMockInitialValues({}));
  for (final size in [
    const Size(1280, 900),
    const Size(960, 640),
    const Size(430, 620),
  ]) {
    testWidgets(
      'thread dialog inherits app scope, pages, replies and navigates $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final site = ThreadSite(),
            app =
                AppState(
                    siteApi: site,
                    serviceApi: FakeService(),
                    socketFactory: OfflineSocket.new,
                  )
                  ..user = Map.from(FakeSite.user)
                  ..starting = false;
        DeskRoute? opened;
        int refreshed = 0;
        final shot = GlobalKey();
        final tile = {
          'id': 21,
          'post_id': 7,
          'user_id': 77,
          'user': {'id': 77, 'nickname': '讨论发起人'},
          'content': '合成主评论',
          'comment_count': 8,
          'children': {'data': []},
          'vote_count': 0,
        };
        // DeskScope intentionally lives below Navigator, exactly like DesktopShell.
        await tester.pumpWidget(
          RepaintBoundary(
            key: shot,
            child: MaterialApp(
              theme: XingyuApp(app: app).theme(Brightness.light),
              home: Scaffold(
                body: DeskScope(
                  app: app,
                  open: (r) => opened = r,
                  child: SingleChildScrollView(
                    child: CommentTile(
                      tile,
                      7,
                      liked: const {},
                      onChange: () => refreshed++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('查看全部回复 · 8'));
        await tester.pumpAndSettle();
        expect(find.text('讨论回复'), findsOneWidget);
        expect(
          find.textContaining('第1页回复 0', findRichText: true),
          findsOneWidget,
        );
        expect(find.textContaining('Null check'), findsNothing);
        expect(tester.takeException(), isNull);
        final liked = find
            .descendant(
              of: find.byType(Dialog),
              matching: find.widgetWithIcon(TextButton, Icons.favorite),
            )
            .first;
        await tester.ensureVisible(liked);
        await tester.tap(liked);
        await tester.pumpAndSettle();
        expect(site.writes.last.$1, 'comment/unvote');
        expect(site.writes.last.$2['id'], 110);
        final scrolling = find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(find.byType(Dialog)),
            scrollDelta: const Offset(0, 220),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.state<ScrollableState>(scrolling).position.pixels,
          greaterThan(0),
        );
        expect(
          site.reads.where((e) => e.$1 == 'comment/list').last.$2['parent_id'],
          21,
        );
        expect(
          site.reads.where((e) => e.$1 == 'comment/list').last.$2['post_id'],
          7,
        );
        final next = find.widgetWithText(OutlinedButton, '下一页');
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('第2页回复 0', findRichText: true),
          findsOneWidget,
        );
        final reply = find
            .descendant(
              of: find.byType(Dialog),
              matching: find.widgetWithText(TextButton, '回复'),
            )
            .first;
        await tester.ensureVisible(reply);
        await tester.tap(reply);
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsOneWidget);
        await tester.enterText(find.byType(TextField), '合成回复，不会请求官网');
        final send = find.widgetWithText(FilledButton, '发布');
        await tester.tap(send);
        await tester.pumpAndSettle();
        expect(site.writes.last.$1, 'comment/create');
        expect(site.writes.last.$2['parent_id'], 21);
        expect(site.writes.last.$2['post_id'], 7);
        expect(site.writes.last.$2['reply_to_id'], 120);
        await capture(tester, shot, 'desktop-discussion-${size.width.toInt()}');
        final avatar = find
            .descendant(of: find.byType(Dialog), matching: find.byType(Avatar))
            .last;
        await tester.ensureVisible(avatar);
        await tester.tap(avatar);
        await tester.pumpAndSettle();
        expect(opened?.kind, 'author');
        expect(opened?.id, 77);
        expect(find.text('讨论回复'), findsNothing);
        expect(refreshed, greaterThan(0));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      },
    );
  }
  testWidgets('switching account hides old discussion data', (tester) async {
    final site = ThreadSite(),
        app = AppState(siteApi: site, serviceApi: FakeService())
          ..user = Map.from(FakeSite.user)
          ..starting = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeskScope(
            app: app,
            open: (_) {},
            child: Builder(
              builder: (c) => TextButton(
                onPressed: () => showDiscussionReplies(
                  c,
                  post: 7,
                  root: 21,
                  locked: false,
                  onChanged: () {},
                ),
                child: const Text('打开讨论'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开讨论'));
    await tester.pumpAndSettle();
    app.user = {'id': 999};
    app.generation++;
    app.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('账号状态已变化'), findsOneWidget);
    expect(find.textContaining('第1页回复', findRichText: true), findsNothing);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
