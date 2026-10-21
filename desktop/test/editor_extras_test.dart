import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/editor_extra_rules.dart';
import 'package:xingyu_desktop/pages/editor_extras.dart';

Json pollFixture() => {
  'title': '选择 <作品>',
  'options': [
    {'id': 11, 'text': '甲', 'image': ''},
    {'id': 12, 'text': '乙', 'image': ''},
  ],
  'image_mode': false,
  'multi_select': true,
  'max_select': 2,
  'start_at': '2026-10-21 12:00:00',
  'end_at': '2026-10-22 12:00:00',
};

class ExtrasFakeApi extends SiteApi {
  final calls = <String>[];
  final writes = <Json>[];
  int nextPoll = 8;
  @override
  Future<Json> get(String path, [Map<String, dynamic>? params]) async {
    calls.add('$path:${params?['search'] ?? ''}');
    if (path == 'poll/info') {
      return {
        'data': {'id': 7, ...pollFixture()},
      };
    }
    return {
      'data': [
        {
          'id': 7,
          'user_id': 47,
          'title': '合成投票',
          'image_mode': false,
          'multi_select': false,
        },
      ],
      'meta': {
        'pagination': {'total_pages': 2},
      },
    };
  }

  @override
  Future<Json> post(String path, Json body) async {
    calls.add(path);
    writes.add(body);
    return {
      'data': {'id': nextPoll},
    };
  }
}

void main() {
  test('local insertions escape user content and retain website shortcode contracts', () {
    expect(
      extraCollapse('[引号"]', '<script>\n第二行', true),
      contains('【引号&quot;】'),
    );
    expect(extraCollapse('标题', '一\n二', false), contains('<p>一<br>二</p>'));
    expect(extraReference('poll', 8), '[poll id="8"][/poll]');
    expect(() => extraReference('lottery', 0), throwsFormatException);
    expect(() => extraInline('onclick=bad', 'a'), throwsFormatException);
    expect(
      extraInline('text-rainbow', '<b>字</b>'),
      '<span class="text-rainbow"><b>字</b></span>',
    );
    for (var i = 0; i < 20; i++) {
      expect(extraRandomName(), matches(RegExp(r'^\[GalACG\]EX\d{9}$')));
    }
    expect(
      extraLotteryAllowed({
        'roles': [
          {'name': 'contributor'},
        ],
      }),
      isFalse,
    );
    expect(
      extraLotteryAllowed({
        'roles': ['editor'],
      }),
      isTrue,
    );
  });
  test('image replace, unlink, sizes and blur preserve attributes without stale lazy URL', () {
    const original =
        '<a href="https://old.example/a"><img src="https://img.example/old.png" data-src="https://img.example/old.png" class="custom" data-id="88" style="color:red;width:12px;height:20px" alt="old"></a>';
    final updated = extraUpdateImage(
      original,
      src: 'https://img.example/new.png',
      alt: '<说明>',
      width: '320',
      height: '50%',
      blur: true,
      link: 'https://example.com/?x=1&y=2',
    );
    final img = html.parseFragment(updated).querySelector('img')!;
    expect(img.attributes['data-id'], '88');
    expect(img.attributes['data-src'], isNull);
    expect(img.classes, containsAll(['custom', 'blur-img']));
    expect(img.attributes['alt'], '<说明>');
    expect(img.attributes['width'], '320');
    expect(
      img.attributes['style'],
      allOf(
        contains('color:red'),
        contains('height:50%'),
        isNot(contains('width:12px')),
      ),
    );
    expect(img.parent!.attributes['href'], 'https://example.com/?x=1&y=2');
    expect(
      html
          .parseFragment(
            extraUpdateImage(
              original,
              src: 'https://img.example/old.png',
              alt: 'old',
            ),
          )
          .querySelector('a'),
      isNull,
    );
    expect(
      () => extraUpdateImage(original, src: 'javascript:alert(1)', alt: ''),
      throwsFormatException,
    );
    expect(
      () => extraUpdateImage(
        original,
        src: 'https://img.example/a',
        alt: '',
        width: '0',
      ),
      throwsFormatException,
    );
  });
  test('table configuration preserves untouched rich cells, captions and safe text changes', () {
    const original =
        '<table data-id="7" style="color:blue;width:20px;height:30px"><caption>标题</caption><tbody><tr><th><a href="https://example.com">甲</a></th><td>乙</td></tr></tbody></table>';
    final output = extraTable(
      original,
      rowCount: 2,
      columnCount: 2,
      cells: ['甲', '<img onerror=x>', '丙', '丁'],
      width: '100%',
      border: 'dashed',
      align: 'center',
    );
    final table = html.parseFragment(output).querySelector('table')!;
    expect(table.attributes['data-id'], '7');
    expect(table.querySelector('caption')!.text, '标题');
    expect(table.querySelector('a'), isNotNull);
    expect(table.querySelector('img'), isNull);
    expect(table.querySelectorAll('tr'), hasLength(2));
    expect(table.classes, contains('fr-dashed-borders'));
    expect(
      table.attributes['style'],
      allOf(contains('width:100%'), isNot(contains('height:'))),
    );
    expect(
      () => extraTable(
        '<table><tr><td colspan="2">x</td></tr></table>',
        rowCount: 1,
        columnCount: 1,
        cells: ['x'],
      ),
      throwsFormatException,
    );
    expect(
      () => extraTable('', rowCount: 31, columnCount: 1, cells: []),
      throwsFormatException,
    );
  });
  test(
    'poll payload validates all fields, dates and keeps option IDs on edit',
    () {
      final input = pollFixture(), value = extraPollPayload(input);
      expect(value['options'][0]['id'], 11);
      expect(value['max_select'], 2);
      expect(value['start_at'], '2026-10-21 12:00:00');
      expect(
        () => extraPollPayload({...input, 'max_select': 1}),
        throwsFormatException,
      );
      expect(
        () => extraPollPayload({...input, 'image_mode': true}),
        throwsFormatException,
      );
      expect(
        () => extraPollPayload({...input, 'end_at': '2026-02-30 12:00:00'}),
        throwsFormatException,
      );
      expect(
        () => extraPollPayload({...input, 'end_at': '2026-10-20 12:00:00'}),
        throwsFormatException,
      );
      expect(() => extraWeb('https://u:p@example.com'), throwsFormatException);
      expect(
        extraWeb('https://example.com/running.png'),
        'https://example.com/running.png',
      );
    },
  );
  testWidgets(
    'poll chooser queries own account, searches and inserts without posting',
    (tester) async {
      final api = ExtrasFakeApi();
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showEditorExtra(
                    context,
                    'poll',
                    api: api,
                    account: {
                      'id': 47,
                      'permissions': ['edit_polls'],
                    },
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('合成投票'), findsNothing);
      expect(find.text('#7  合成投票'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '关键字');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(api.calls.last, 'poll/list:关键字');
      await tester.tap(find.text('插入'));
      await tester.pumpAndSettle();
      expect(result, '[poll id="7"][/poll]');
      expect(api.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('poll create is explicit and supports uploaded option images', (
    tester,
  ) async {
    final api = ExtrasFakeApi();
    var uploads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showEditorExtra(
                context,
                'poll',
                api: api,
                account: {
                  'id': 47,
                  'permissions': ['edit_polls'],
                },
                uploadImage: () async {
                  uploads++;
                  return 'https://images.example/upload.png';
                },
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建投票'));
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '新投票');
    await tester.enterText(fields.at(2), '选项甲');
    await tester.enterText(fields.at(3), '选项乙');
    await tester.ensureVisible(find.text('图片模式（每项需图片）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('图片模式（每项需图片）'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('上传选项图片').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('上传选项图片').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('上传选项图片').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('上传选项图片').last);
    await tester.pumpAndSettle();
    expect(uploads, 2);
    await tester.tap(find.text('保存到官网'));
    await tester.pumpAndSettle();
    expect(api.writes, hasLength(1));
    expect(api.writes.single['image_mode'], isTrue);
    expect(
      api.writes.single['options'][0]['image'],
      'https://images.example/upload.png',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'image dialog replaces local image and preserves full original properties',
    (tester) async {
      String? result;
      var uploads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await editEditorImage(
                    context,
                    '<img src="https://img.example/old.png" alt="原说明" class="custom" data-id="77">',
                    uploadImage: () async {
                      uploads++;
                      return 'https://img.example/upload.png';
                    },
                  );
                },
                child: const Text('打开图片'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开图片'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从设备选择替换图片'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      final img = html.parseFragment(result!).querySelector('img')!;
      expect(uploads, 1);
      expect(img.attributes['src'], 'https://img.example/upload.png');
      expect(img.attributes['alt'], '原说明');
      expect(img.attributes['data-id'], '77');
      expect(img.classes, contains('custom'));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'table dialog changes cells without discarding rich unedited content',
    (tester) async {
      final api = ExtrasFakeApi();
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showEditorExtra(
                    context,
                    'table',
                    api: api,
                    selectedHtml: '<table data-id="77"><tbody><tr><td><b>甲</b></td><td>乙</td></tr></tbody></table>',
                  );
                },
                child: const Text('打开表格'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开表格'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(3), '新乙');
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      final table = html.parseFragment(result!).querySelector('table')!;
      expect(table.attributes['data-id'], '77');
      expect(table.querySelector('b')!.text, '甲');
      expect(table.querySelectorAll('td').last.text, '新乙');
      expect(api.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('stale poll editor blocks writes after account switches', (
    tester,
  ) async {
    final api = ExtrasFakeApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showEditorExtra(
                context,
                'poll',
                api: api,
                account: {
                  'id': 47,
                  'permissions': ['edit_polls'],
                },
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建投票'));
    await tester.pumpAndSettle();
    api.generation++;
    await tester.tap(find.text('保存到官网'));
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    expect(find.textContaining('账号已切换'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
