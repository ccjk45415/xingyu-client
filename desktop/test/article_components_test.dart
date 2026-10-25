import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/reader.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/core/state.dart';
import 'package:xingyu_desktop/ui/article_lottery.dart';
import 'package:xingyu_desktop/ui/category_tab_strip.dart';
import 'package:xingyu_desktop/ui/shared.dart';

import 'widget_test.dart' show FakeSite, FakeService, OfflineSocket, frames;

class LotterySite extends FakeSite {
  Json detail = {
    'id': 134,
    'name': '合成抽奖活动',
    'point': 10,
    'prizes': [
      {'name': '合成奖品', 'count': 3},
    ],
    'participated': false,
    'participant_count': 9,
    'is_finished': false,
    'is_published': false,
  };
  int writes = 0;
  bool lostResponse = false;
  Completer<Json>? pending;
  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) async {
    if (path == 'lottery/info') {
      expect(params?['id'], 134);
      return pending?.future ?? {'code': 0, 'data': Map.from(detail)};
    }
    if (path == 'lottery/winners') {
      expect(params?['with[0]'], 'user');
      return {
        'code': 0,
        'data': [
          {
            'prize': 0,
            'user': {'nickname': '<b>测试用户</b>'},
          },
        ],
      };
    }
    return super.get(path, params);
  }

  @override
  Future<Json> post(String path, Json body) async {
    expect(path, 'lottery/participate');
    expect(body, {'id': '134'});
    writes++;
    detail['participated'] = true;
    if (lostResponse) throw TimeoutException('synthetic');
    return {'code': 0};
  }
}

void main() {
  test('lottery shortcodes render but code examples remain inert; Shanghai times respected', () {
    final parsed = ReaderDocument.parse(
      '<p>[lottery id="134"][/lottery]</p><pre>[lottery id="9"][/lottery]</pre>',
    ).content;
    expect(parsed, contains('class="xingyu-lottery" data-id="134"'));
    expect(parsed, contains('<pre>[lottery id="9"][/lottery]</pre>'));
    expect(parsed, isNot(contains('data-id="9"')));
    expect(
      readerLotteryMarkup('[lottery id="x"][/lottery]'),
      isNot(contains('xingyu-lottery')),
    );
    expect(lotteryTime('2026-10-25 12:00:00'), DateTime.utc(2026, 10, 25, 4));
    expect(
      lotteryCanEnter({
        'id': 1,
        'end_at': '2026-10-24 20:00:00',
      }, DateTime.utc(2026, 10, 25)),
      isFalse,
    );
  });
  Future<AppState> mount(WidgetTester tester, LotterySite site) async {
    SecureVault.setMockInitialValues({});
    final app =
        AppState(
            siteApi: site,
            serviceApi: FakeService(),
            socketFactory: OfflineSocket.new,
          )
          ..starting = false
          ..user = Map.from(FakeSite.user);
    await tester.pumpWidget(
      MaterialApp(
        home: DeskScope(
          app: app,
          open: (_) {},
          child: Scaffold(
            body: SingleChildScrollView(
              child: RichContent(
                ReaderDocument.parse('[lottery id="134"][/lottery]').content,
              ),
            ),
          ),
        ),
      ),
    );
    await frames(tester);
    return app;
  }

  Future<void> close(WidgetTester tester, AppState app) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
    app.dispose();
  }

  testWidgets(
    'lottery cancel never charges; explicit confirm submits once and reconciles lost response',
    (tester) async {
      final site = LotterySite()..lostResponse = true;
      final app = await mount(tester, site);
      expect(find.text('合成抽奖活动'), findsOneWidget);
      await tester.tap(find.text('参与抽奖'));
      await tester.pumpAndSettle();
      expect(find.textContaining('将扣除 10 点积分'), findsOneWidget);
      expect(site.writes, 0);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(site.writes, 0);
      await tester.tap(find.text('参与抽奖'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认参与'));
      await tester.pumpAndSettle();
      expect(site.writes, 1);
      expect(find.text('已参与'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester, app);
    },
  );
  testWidgets(
    'published results render nickname as text; stale account cannot participate',
    (tester) async {
      final site = LotterySite()..detail['is_published'] = true;
      final app = await mount(tester, site);
      await tester.tap(find.text('查看中奖用户'));
      await tester.pumpAndSettle();
      expect(find.text('合成奖品：<b>测试用户</b>'), findsOneWidget);
      expect(site.writes, 0);
      await close(tester, app);
      final site2 = LotterySite();
      // Holding the live-state read prevents an old account's confirmation dialog.
      final app3 = await mount(tester, site2);
      site2.pending = Completer<Json>();
      await tester.tap(find.text('参与抽奖'));
      await tester.pump();
      app3.user = {'id': 88};
      site2.pending!.complete({'code': 0, 'data': site2.detail});
      await tester.pumpAndSettle();
      expect(find.text('确认参与'), findsNothing);
      expect(site2.writes, 0);
      await close(tester, app3);
    },
  );
  testWidgets(
    'two category levels have independent draggable thumbs and mouse-wheel scrolling',
    (tester) async {
      tester.view.physicalSize = const Size(640, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                for (final level in [0, 1])
                  CategoryTabStrip(
                    key: ValueKey('level$level'),
                    children: [
                      for (var i = 0; i < 20; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('分类 $level-$i'),
                            selected: false,
                            onSelected: (_) {},
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bars = tester
          .widgetList<Scrollbar>(find.byType(Scrollbar))
          .toList();
      expect(bars, hasLength(2));
      expect(
        bars.every(
          (bar) => bar.thumbVisibility == true && bar.interactive == true,
        ),
        isTrue,
      );
      final first = bars[0].controller!, second = bars[1].controller!;
      final position = tester.getCenter(find.byKey(const ValueKey('level0')));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(0, 230),
        ),
      );
      await tester.pumpAndSettle();
      expect(first.offset, greaterThan(0));
      expect(second.offset, 0);
      first.jumpTo(first.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('分类 0-19').hitTestable(), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('level1')),
        const Offset(-250, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(second.offset, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'original-site action launches externally while normal article links stay internal',
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      SecureVault.setMockInitialValues({});
      final app = AppState(
        siteApi: FakeSite(),
        serviceApi: FakeService(),
        socketFactory: OfflineSocket.new,
      )..starting = false;
      final routes = <DeskRoute>[];
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: DeskScope(
            app: app,
            open: routes.add,
            child: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await openLink(context, 'https://cangku.moe/archives/229761');
      expect(routes.single.id, 229761);
      expect(calls, isEmpty);
      await openLink(
        context,
        'https://cangku.moe/archives/229761',
        external: true,
      );
      expect(routes, hasLength(1));
      expect(
        calls.single.arguments['url'],
        'https://cangku.moe/archives/229761',
      );
      await close(tester, app);
    },
  );
}
