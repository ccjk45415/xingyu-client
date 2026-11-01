import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/ui/comment_reply_preview.dart';

Widget preview({
  int loaded = 8,
  int total = 80,
  Key? thread,
  VoidCallback? onViewAll,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: CommentReplyPreview(
        key: thread,
        total: total,
        onViewAll: onViewAll ?? () {},
        replies: [
          for (var i = 1; i <= loaded; i++)
            SizedBox(height: 30, child: Text('测试回复 $i')),
        ],
      ),
    ),
  ),
);

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets('long reply previews expand and collapse at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = 0;
      await tester.pumpWidget(preview(onViewAll: () => opened++));
      expect(find.text('测试回复 1'), findsOneWidget);
      expect(find.text('测试回复 3'), findsOneWidget);
      expect(find.text('测试回复 4'), findsNothing);
      expect(find.text('展开剩余 5 条回复'), findsOneWidget);
      // Eight cached replies are distinct from the full thread's eighty.
      expect(find.text('查看全部回复 · 80'), findsOneWidget);

      await tester.tap(find.byKey(const Key('comment.replies.toggle')));
      await tester.pumpAndSettle();
      expect(find.text('测试回复 8'), findsOneWidget);
      expect(find.text('收起回复'), findsOneWidget);
      await tester.tap(find.text('查看全部回复 · 80'));
      expect(opened, 1);
      await tester.tap(find.text('收起回复'));
      await tester.pumpAndSettle();
      expect(find.text('测试回复 4'), findsNothing);
      expect(find.text('测试回复 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('small threads and unloaded replies retain full-thread access', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(preview(loaded: 2, total: 2));
    expect(find.text('测试回复 2'), findsOneWidget);
    expect(find.byKey(const Key('comment.replies.toggle')), findsNothing);
    expect(find.text('查看全部回复 · 2'), findsOneWidget);

    await tester.pumpWidget(
      preview(loaded: 0, total: 17, onViewAll: () => opened++),
    );
    expect(find.text('查看全部回复 · 17'), findsOneWidget);
    await tester.tap(find.text('查看全部回复 · 17'));
    expect(opened, 1);

    await tester.pumpWidget(preview(loaded: 0, total: 0));
    expect(find.byType(TextButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'stale totals do not hide loaded replies; changing thread resets',
    (tester) async {
      await tester.pumpWidget(preview(total: 2, thread: const ValueKey('one')));
      expect(find.text('查看全部回复 · 8'), findsOneWidget);
      await tester.tap(find.byKey(const Key('comment.replies.toggle')));
      await tester.pumpAndSettle();
      expect(find.text('测试回复 8'), findsOneWidget);

      await tester.pumpWidget(preview(thread: const ValueKey('two')));
      expect(find.text('测试回复 4'), findsNothing);
      expect(find.text('展开剩余 5 条回复'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
