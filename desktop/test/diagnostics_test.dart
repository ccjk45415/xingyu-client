import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/error_diagnostics.dart';
import 'package:xingyu_desktop/core/native_storage.dart';
import 'package:xingyu_desktop/pages/diagnostics.dart';

import 'widget_test.dart' show capture;

class BrokenVault extends SecureVault {
  @override
  Future<String?> read({required String key}) async =>
      throw StateError('sensitive');
  @override
  Future<void> write({required String key, required String value}) async =>
      throw StateError('sensitive');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [
      (
        'MaterialIcons',
        'C:/codex-tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ),
      ('Microsoft YaHei UI', 'C:/Windows/Fonts/msyh.ttc'),
      ('Consolas', 'C:/Windows/Fonts/consola.ttf'),
    ]) {
      final file = File(font.$2);
      if (await file.exists()) {
        await (FontLoader(
          font.$1,
        )..addFont(file.readAsBytes().then(ByteData.sublistView))).load();
      }
    }
  });
  setUp(
    () => SecureVault.setMockInitialValues({'session': 'keep-this-session'}),
  );
  test(
    'diagnostics exclude error messages, URLs, home paths and source inputs',
    () async {
      final store = DiagnosticStore();
      await store.record(
        StateError('password=secret API_KEY user draft'),
        StackTrace.fromString(
          '#0 callback (package:xingyu_desktop/pages/authoring.dart:14:3)\n#1 private (file:///C:/Users/private-user/draft.dart:20:5)\nhttps://api.example/?key=private-key',
        ),
        'flutter',
      );
      final report = store.report();
      expect(report, contains('StateError'));
      expect(
        report,
        contains('package:xingyu_desktop/pages/authoring.dart:14:3'),
      );
      for (final secret in [
        'password=',
        'secret',
        'API_KEY',
        'private-user',
        'private-key',
        'draft.dart',
        'api.example',
        'user draft',
      ]) {
        expect(report, isNot(contains(secret)));
      }
      final restored = DiagnosticStore();
      await restored.initialize();
      expect(restored.entries.length, 1);
      expect(restored.entries.first.frames, store.entries.first.frames);
    },
  );
  test('concurrent errors are persisted in order and bounded to ten', () async {
    final store = DiagnosticStore();
    await Future.wait([
      for (int i = 0; i < 24; i++)
        store.record(
          StateError('ignored'),
          StackTrace.fromString(
            '#0 fn (package:xingyu_desktop/app.dart:${100 + i}:1)',
          ),
          'zone',
        ),
    ]);
    expect(store.entries.length, 10);
    expect(store.entries.first.frames, contains(':123:1'));
    final restored = DiagnosticStore();
    await restored.initialize();
    expect(restored.entries.length, 10);
    expect(restored.entries.first.frames, store.entries.first.frames);
    final stored = await const SecureVault().read(
      key: DiagnosticStore.storageKey,
    );
    expect((jsonDecode(stored!) as List).length, 10);
  });
  test('clearing diagnostics does not clear login storage', () async {
    final store = DiagnosticStore();
    await store.record(StateError('x'), StackTrace.current, 'flutter');
    await store.clear();
    final restored = DiagnosticStore();
    await restored.initialize();
    expect(restored.entries, isEmpty);
    expect(store.report(), contains('暂无异常记录'));
    expect(await const SecureVault().read(key: 'session'), 'keep-this-session');
  });
  test(
    'broken storage retains a bounded memory report without rethrowing',
    () async {
      final store = DiagnosticStore(vault: BrokenVault());
      await store.record(StateError('secret'), StackTrace.current, 'platform');
      expect(store.entries.length, 1);
      expect(store.storageAvailable, isFalse);
      expect(store.report(), contains('安全存储暂不可用'));
      expect(store.report(), isNot(contains('secret')));
    },
  );
  test('malformed or oversized stored records are ignored', () async {
    for (final raw in ['invalid-json', 'x' * 200000]) {
      SecureVault.setMockInitialValues({DiagnosticStore.storageKey: raw});
      final store = DiagnosticStore();
      await store.initialize();
      expect(store.entries, isEmpty);
      await store.record(StateError('x'), StackTrace.current, 'flutter');
      expect(store.entries.length, 1);
    }
  });
  for (final size in [const Size(1100, 740), const Size(450, 600)]) {
    testWidgets('diagnostic panel copy and clear at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final store = DiagnosticStore();
      await store.record(
        StateError('private body'),
        StackTrace.fromString('#0 fn (package:xingyu_desktop/app.dart:123:4)'),
        'flutter',
      );
      final shot = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: shot,
          child: MaterialApp(
            theme: ThemeData(fontFamily: 'Microsoft YaHei UI'),
            home: Scaffold(
              body: Builder(
                builder: (c) => TextButton(
                  onPressed: () => showDiagnostics(c, store: store),
                  child: const Text('打开诊断'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开诊断'));
      await tester.pumpAndSettle();
      expect(find.text('诊断信息'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, shot, 'desktop-diagnostics-${size.width.toInt()}');
      await tester.tap(find.text('复制诊断'));
      await tester.pumpAndSettle();
      expect(copied, contains('StateError'));
      expect(copied, isNot(contains('private body')));
      await tester.tap(find.text('清空记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '清空'));
      await tester.pumpAndSettle();
      expect(store.entries, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  }
}
