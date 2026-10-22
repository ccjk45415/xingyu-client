import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/ai.dart';
import 'package:xingyu_desktop/core/source_document.dart';
import 'package:xingyu_desktop/core/translation.dart';

void main() {
  test('titles stay original in local plans and legacy built-in recovery', () {
    final sources = <Json>[
      {
        'url': 'https://example.com/a',
        'title': '原作タイトル 😀',
        'cover': '',
        'blocks': [
          {'kind': 'p', 'text': 'First description.'},
          {'kind': 'image', 'url': 'https://example.com/a.png', 'alt': '原图'},
        ],
      },
      {
        'url': 'https://example.com/b',
        'title': 'Другой мир',
        'cover': '',
        'blocks': [
          {'kind': 'p', 'text': 'Second description.'},
        ],
      },
    ];
    final request = translationRequest(sources, '补充', 'other', 'test-request');
    final plan = TranslationPlan(sources), values = <String, String>{};
    for (final chunk in plan.chunks) {
      for (final segment in chunk) {
        expect(segment['text'], isNot(anyOf('原作タイトル 😀', 'Другой мир')));
        values[text(segment['id'])] = '译文';
      }
    }
    final local = plan.assemble(sources, 'other', values);
    expect(local['title'], '原作タイトル 😀');
    expect(rows(local['blocks'])[2]['text'], 'Другой мир');
    final wire = builtinBodyOnlyRequest(request);
    expect(rows(wire['sources']).map((s) => s['title']), ['', '']);
    expect(rows(request['sources']).first['title'], '原作タイトル 😀');
    final raw = <String, dynamic>{
      'title': '作品介绍',
      'blocks': [
        {'kind': 'p', 'text': '第一段译文'},
        {'kind': 'image', 'url': 'https://example.com/a.png', 'alt': '原图'},
        {'kind': 'p', 'text': '补充译文'},
        {'kind': 'p', 'text': '第二段译文'},
      ],
    };
    final recovered = restoreOriginalSourceTitles(raw, request);
    expect(recovered['title'], '原作タイトル 😀');
    expect(rows(recovered['blocks']).map((b) => b['kind']), [
      'p',
      'image',
      'p',
      'h2',
      'p',
    ]);
    expect(rows(recovered['blocks'])[3]['text'], 'Другой мир');
    expect(raw['blocks'], hasLength(4));
    expect(
      () => restoreOriginalSourceTitles({'blocks': []}, request),
      throwsA(isA<ApiFailure>()),
    );
    final noTitle = TranslationPlan([
      {...sources.first, 'title': ''},
    ]);
    final same = <String, String>{};
    for (final chunk in noTitle.chunks) {
      for (final s in chunk) {
        same[text(s['id'])] = text(s['text']);
      }
    }
    expect(
      noTitle.assemble(
        [
          {...sources.first, 'title': ''},
        ],
        'other',
        same,
      )['title'],
      '',
    );
  });
  test('region-limited page is never mistaken for a complete introduction', () {
    expect(
      () => parseSourceDocument(
        '<div class="error_box_work">お住いの国・地域からは購入できません。</div>',
        Uri.parse('https://www.dlsite.com/maniax/work'),
      ),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.toString(),
          'message',
          contains('出口地区'),
        ),
      ),
    );
  });
  test('detailed DOM beats SEO and metadata, lazy and inline images remain between original text blocks', () async {
    final root = Directory(Directory.current.resolveSymbolicLinksSync())
        .parent
        .path;
    final source = parseSourceDocument(
      await File('$root/tests/fixtures/source-introduction.html')
          .readAsString(),
      Uri.parse(
        'https://www.dlsite.com/maniax/work/=/product_id/RJ00000001.html',
      ),
    );
    expect(source['title'], '小さな冒険');
    expect(text(source['text']).contains('DO_NOT_COPY'), false);
    expect(text(source['text']).contains('SEO'), false);
    final blocks = rows(source['blocks']);
    expect(blocks[2]['kind'], 'image');
    expect(blocks[2]['url'], 'https://cdn.example.com/detail-a.jpg');
    expect(blocks[3]['text'], 'First half');
    expect(blocks[4]['kind'], 'image');
    expect(blocks[5]['text'], 'second half.');
    final plan = TranslationPlan([source]), values = <String, String>{};
    for (final c in plan.chunks) {
      values.addAll(parseTranslations({'translations': c}, c));
    }
    final draft = AiDraft.parse(plan.assemble([source], 'auto', values), [
      source,
    ], service: true);
    expect(
      draft.body.indexOf('First half'),
      lessThan(draft.body.indexOf('detail-b.png')),
    );
    expect(
      draft.body.indexOf('detail-b.png'),
      lessThan(draft.body.indexOf('second half.')),
    );
    expect(draft.body, contains('日本語の画像'));
    expect(draft.tags, isEmpty);
  });
  test('long introduction joins without losing Unicode, text or pictures and missing translation is never accepted', () {
    final original = '${'A' * 799}😀${'文' * 2000}',
        source = <String, dynamic>{
          'url': 'https://example.com/work',
          'title': '',
          'cover': '',
          'blocks': [
            {'kind': 'p', 'text': original},
          ],
        };
    final plan = TranslationPlan([source]), values = <String, String>{};
    for (final c in plan.chunks) {
      values.addAll(parseTranslations({'translations': c}, c));
    }
    expect(plan.chunks.length, greaterThan(1));
    expect(
      rows(plan.assemble([source], 'auto', values)['blocks']).first['text'],
      original,
    );
    expect(
      () => parseTranslations({'translations': []}, plan.chunks.first),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      desktopSourceUri(
        Uri.parse(
          'https://www.dlsite.com/maniax-touch/work/=/product_id/RJ1.html',
        ),
      ).path,
      startsWith('/maniax/'),
    );
  });
}
