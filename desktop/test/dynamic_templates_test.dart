import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/dynamic_template_store.dart';
import 'package:xingyu_desktop/core/dynamic_templates.dart';
import 'package:xingyu_desktop/core/submission_guidance.dart';
import 'package:xingyu_desktop/core/submission_workbench.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  DynamicTemplate game() => starterDynamicTemplates().first;
  void setFields(Json task, Json values) {
    task['fields'] = {...object(task['fields']), ...values};
  }

  Json ready() {
    final task = newDynamicTask(game());
    task['fields'] = {
      'title': 'Original title',
      'source_urls': [
        'https://www.dlsite.com/maniax/work/=/product_id/RJ0169492.html',
      ],
      'cover': 'https://file.cangku.moe/cover.jpg',
      'description': '真实作品介绍',
      'purchased': false,
      'downloads': [
        {
          'name': '百度网盘',
          'url': 'https://pan.baidu.com/s/real',
          'code': '1234',
          'password': 'DO-NOT-INDEX',
        },
      ],
    };
    task['category_ids'] = [1];
    return task;
  }

  group('dynamic template rules and render', () {
    test('mixed store and download links stay separate in one message', () {
      final task = newDynamicTask(game());
      absorbDynamicMessage(
        task,
        '游戏链接：https://store.steampowered.com/app/12345\n下载链接：https://pan.baidu.com/s/real 提取码：abcd',
      );
      final fields = object(task['fields']);
      expect(fields['source_urls'], [
        'https://store.steampowered.com/app/12345',
      ]);
      expect(
        rows(fields['downloads']).single['url'],
        'https://pan.baidu.com/s/real',
      );
      expect(rows(fields['downloads']).single['code'], 'abcd');
    });
    test('RJ shorthand resolves to a concrete public DLsite source', () {
      final task = newDynamicTask(game());
      absorbDynamicMessage(task, '帮我整理 RJ0169492');
      expect(object(task['fields'])['source_urls'], [
        'https://www.dlsite.com/maniax/work/=/product_id/RJ0169492.html',
      ]);
    });
    test('natural language edits preserve images and video blocks', () {
      final task = newDynamicTask(game());
      task['sources'] = [
        {
          'url': 'https://example.org/work',
          'text': '作品介绍',
          'blocks': [
            {'kind': 'p', 'text': '作品介绍'},
            {'kind': 'image', 'url': 'https://example.org/shot.jpg'},
            {
              'kind': 'video',
              'url': 'https://example.org/movie.mp4',
              'title': '作品视频',
            },
          ],
        },
      ];
      final document = WorkDocument(dynamicDescription(task));
      final body = document.apply([
        {'id': document.segments.first['id'], 'text': '精简后的介绍'},
      ]);
      expect(body, contains('精简后的介绍'));
      expect(body, contains('https://example.org/shot.jpg'));
      expect(body, contains('https://example.org/movie.mp4'));
    });
    test('cover and proof URLs use their own line labels', () {
      final task = newDynamicTask(game());
      absorbDynamicMessage(
        task,
        '封面：https://file.cangku.moe/cover.jpg\n自购证明：https://file.cangku.moe/proof.jpg',
      );
      expect(
        object(task['fields'])['cover'],
        'https://file.cangku.moe/cover.jpg',
      );
      expect(
        object(task['fields'])['proof'],
        'https://file.cangku.moe/proof.jpg',
      );
    });
    test('conditional purchase requirement and false branch', () {
      final task = ready();
      expect(dynamicMissing(task), isEmpty);
      absorbDynamicMessage(task, '这是自购作品');
      expect(dynamicMissing(task), ['proof']);
      absorbDynamicMessage(task, '不是自购');
      expect(dynamicMissing(task), isEmpty);
    });
    test('website source alternatives require one actual HTTPS URL', () {
      final task = ready();
      setFields(task, {
        'source_urls': ['javascript:alert(1)'],
      });
      expect(dynamicMissing(task), contains('source'));
    });
    test('DLsite title appends an RJ code once', () {
      final task = ready();
      expect(dynamicTitle(task), 'Original title [RJ0169492]');
      setFields(task, {'title': 'Original title [RJ0169492]'});
      expect(dynamicTitle(task), 'Original title [RJ0169492]');
    });
    test('purchase proof precedes download even in reordered template', () {
      final task = ready();
      task['template'] = {
        ...game().data,
        'sections': ['metadata', 'description', 'download', 'source', 'proof'],
      };
      setFields(task, {
        'purchased': true,
        'proof': 'https://file.cangku.moe/proof.jpg',
      });
      final body = dynamicBody(task);
      expect(body, contains('data-xingyu-purchase-proof'));
      expect(body.indexOf('自购证明'), lessThan(body.indexOf('[dlbox')));
      expect(body, contains('DO-NOT-INDEX'));
      expect(body, isNot(contains('<li></li>')));
    });
    test('empty metadata does not leave bullets', () {
      final body = dynamicBody(ready());
      expect(body, isNot(contains('<ul></ul>')));
      expect(body, isNot(contains('<li></li>')));
    });
    test('AI instruction omits known private material', () {
      final task = ready();
      final value = dynamicAiInstruction(
        task,
        '缩短作品介绍，https://pan.baidu.com/s/real 密码DO-NOT-INDEX 提取码1234',
      );
      expect(value, isNot(contains('DO-NOT-INDEX')));
      expect(value, isNot(contains('https://pan.baidu.com')));
      expect(value, isNot(contains('1234')));
      expect(value, contains('缩短作品介绍'));
    });
    test('memory summary never copies download passwords or URLs', () {
      final summary = dynamicMemorySummary(
        ready(),
        postId: 9,
        status: 'publish',
      );
      expect(summary, contains('RJ0169492'));
      expect(summary, contains('已发布'));
      expect(summary, isNot(contains('DO-NOT-INDEX')));
      expect(summary, isNot(contains('pan.baidu')));
    });
    test('editor snapshot carries template version and complete fields', () {
      final task = ready(), snapshot = dynamicEditorSnapshot(task, 77);
      expect(snapshot['dynamic_task_id'], task['id']);
      expect(snapshot['dynamic_template_version'], 1);
      expect(snapshot['owner'], 77);
      expect(snapshot['status'], 'draft');
      expect(snapshot['content_format'], 'html');
    });
    test('full published body is not wrapped twice', () {
      final task = ready();
      setFields(task, {
        'full_body': true,
        'body_html': '<h3>原文</h3><p>官网最新稿</p>',
      });
      expect(dynamicBody(task), '<h3>原文</h3><p>官网最新稿</p>');
      expect(dynamicTitle(task), 'Original title');
    });
    test('AI proposal is strictly validated and keeps reference identity', () {
      final base = game();
      final proposed = applyDynamicTemplateProposal(base, {
        'name': '测试模板',
        'kind': 'game',
        'required': ['title', 'source'],
        'sections': ['description', 'download'],
        'proof_when_purchased': true,
        'title_format': '[游戏]{title}{rj}',
        'notes': '需要人工核对',
      });
      expect(proposed.id, base.id);
      expect(proposed.required, {'title', 'source'});
      expect(
        () => applyDynamicTemplateProposal(base, {
          'name': 'x',
          'kind': 'game',
          'required': ['execute_code'],
          'sections': ['description'],
          'proof_when_purchased': true,
        }),
        throwsFormatException,
      );
    });
    test('template refine uses its own bounded two-segment protocol', () {
      final template = DynamicTemplate({
        ...game().data,
        'source_excerpt': List.filled(1900, '🎵').join(),
      });
      final request = dynamicTemplateRefineRequest(
        template,
        requestId: '12345678-1234-1234-1234-123456789012',
      );
      expect(request['task'], 'template_refine');
      expect(request['sources'], isEmpty);
      final segments = rows(request['segments']);
      expect(segments.map((s) => s['id']), ['0', '1']);
      expect(text(segments[1]['text']).runes.length, 1800);
      final current = object(jsonDecode(text(segments[0]['text'])));
      expect(current.keys.toSet(), {
        'name',
        'kind',
        'required',
        'sections',
        'proof_when_purchased',
        'title_format',
        'notes',
      });
      expect(current, isNot(contains('source_excerpt')));
      expect(dynamicTemplateSystem, isNot(contains('preflight')));
    });
    test(
      'direct template JSON accepts notes beyond old 400-char wrapper limit',
      () {
        final proposal = {
          for (final k in [
            'name',
            'kind',
            'required',
            'sections',
            'proof_when_purchased',
            'title_format',
            'notes',
          ])
            k: game().data[k],
        };
        proposal['notes'] = List.filled(220, '说明').join();
        final parsed = parseDynamicTemplateProposal(
          '```json\n${jsonEncode(proposal)}\n```',
          game(),
        );
        expect(text(parsed.data['notes']).length, 440);
        expect(parsed.id, game().id);
      },
    );
    test('template parser rejects old workbench wrapper and unsafe schema', () {
      final valid = {
        for (final k in [
          'name',
          'kind',
          'required',
          'sections',
          'proof_when_purchased',
          'title_format',
          'notes',
        ])
          k: game().data[k],
      };
      for (final invalid in [
        {
          'edits': [],
          'metadata': [],
          'notes': [jsonEncode(valid)],
        },
        {...valid, 'unexpected': true},
        {
          ...valid,
          'required': ['title', 'title'],
        },
        {
          ...valid,
          'sections': ['description', 'description'],
        },
        {...valid, 'sections': []},
        {...valid, 'proof_when_purchased': 'true'},
        {...valid, 'name': 42},
        {...valid, 'notes': '<script>alert(1)</script>'},
        {...valid, 'notes': '[iframe]malicious[/iframe]'},
        {...valid, 'notes': 'javascript:alert(1)'},
        {...valid, 'title_format': '原标题'},
      ]) {
        expect(
          () => parseDynamicTemplateProposal(invalid, game()),
          throwsFormatException,
        );
      }
    });
    test('template title requires original-title placeholder', () {
      expect(
        () => DynamicTemplate({...game().data, 'title_format': '伪造标题'}),
        throwsFormatException,
      );
    });
    test(
      'source title cover metadata and root category fill known fields',
      () async {
        final guide = await SubmissionGuidance.load();
        final task = newDynamicTask(game());
        absorbDynamicSource(
          task,
          {
            'url': 'https://store.steampowered.com/app/2',
            'title': 'Source title',
            'cover': 'https://cdn.example.org/cover.jpg',
            'text': '作品原文',
            'blocks': [
              {'kind': 'p', 'text': '作品原文'},
            ],
          },
          guide,
          [
            {'id': 1, 'name': '游戏', 'children': []},
          ],
        );
        expect(object(task['fields'])['title'], 'Source title');
        expect(task['category_ids'], [1]);
        expect(dynamicBody(task), contains('作品原文'));
      },
    );
    test('web learning produces editable source-provenanced proposal', () {
      final learned = learnDynamicTemplate({
        'title': '游戏分享范例',
        'url': 'https://cangku.moe/archives/1',
        'text': '游戏作品介绍，网盘下载',
        'blocks': [
          {'kind': 'h3', 'text': '作品介绍'},
          {'kind': 'h3', 'text': '下载'},
        ],
      });
      expect(learned.kind, 'game');
      expect(learned.data['source_url'], 'https://cangku.moe/archives/1');
      expect(learned.required, contains('download'));
      expect(
        learned.sections.indexOf('description'),
        lessThan(learned.sections.indexOf('download')),
      );
    });
    test('template matching recommends by natural language aliases', () {
      final found = matchDynamicTemplates(
        starterDynamicTemplates(),
        '帮我按游戏分享整理这个链接',
      );
      expect(found.first.kind, 'game');
    });
  });
  group('local SQLite and retrieval', () {
    late DynamicTemplateStore store;
    setUp(() => store = DynamicTemplateStore(7, sqlite3.openInMemory()));
    tearDown(() => store.close());
    test('template revisions do not mutate existing task snapshot', () {
      final template = store.templates.first;
      final task = newDynamicTask(template);
      store.saveTask(task);
      final next = store.saveTemplate(
        DynamicTemplate({...template.data, 'name': '改过的模板'}),
      );
      expect(next.version, template.version + 1);
      expect(
        object(store.task(text(task['id']))!['template'])['name'],
        template.name,
      );
      expect(store.versions(template.id).length, 2);
    });
    test('all messages persist in order but are not indexed', () {
      final task = ready();
      store.saveTask(task);
      store.addMessage(text(task['id']), 'user', 'PRIVATE-CONVERSATION');
      store.addMessage(text(task['id']), 'tool', '提取记录');
      expect(store.messages(text(task['id'])).map((m) => m['role']), [
        'user',
        'tool',
      ]);
      expect(store.search('PRIVATE-CONVERSATION'), isEmpty);
    });
    test('FTS5 indexes RJ and CJK with short-name fallback', () {
      store.putMemory(
        'test',
        kind: 'submission',
        title: '音声作品',
        content: 'RJ0169492 作品资料',
        taskId: 'task',
      );
      expect(store.search('RJ0169492').single['id'], 'test');
      expect(
        store.search('音声').where((m) => m['id'] == 'test').single['id'],
        'test',
      );
      expect(store.search('作品资料').single['id'], 'test');
      expect(store.search('" OR 1=1 --'), isEmpty);
    });
    test('successful receipt saves final editor body and a unique summary', () {
      final task = ready();
      store.saveTask(task);
      final snapshot = {
        ...dynamicEditorSnapshot(task, 7),
        'title': '编辑后的原标题',
        'content': '<p>编辑器中的最终正文</p>',
      };
      store.markSubmitted(
        text(task['id']),
        postId: 99,
        status: 'publish',
        snapshot: snapshot,
      );
      store.markSubmitted(
        text(task['id']),
        postId: 99,
        status: 'publish',
        snapshot: snapshot,
      );
      final saved = store.task(text(task['id']))!;
      expect(saved['needs_latest'], true);
      expect(dynamicBody(saved), '<p>编辑器中的最终正文</p>');
      expect(saved['post_id'], 99);
      expect(saved['desired_status'], 'publish');
      expect(dynamicEditorSnapshot(saved, 7)['status'], 'publish');
      expect(
        store.search('编辑后的原标题').where((m) => m['kind'] == 'submission').length,
        1,
      );
      expect(store.search('DO-NOT-INDEX'), isEmpty);
    });
    test('website draft does not falsely create published memory', () {
      final task = ready();
      store.saveTask(task);
      store.markSubmitted(text(task['id']), postId: 4, status: 'draft');
      expect(store.task(text(task['id']))!['status'], 'website_draft');
      expect(store.search('Original title'), isEmpty);
    });
    test(
      'receipt keeps the final schedule instead of a stale template default',
      () {
        final task = ready()
          ..['desired_status'] = 'draft'
          ..['schedule'] = 'old schedule';
        store.saveTask(task);
        store.markSubmitted(
          text(task['id']),
          postId: 88,
          status: 'future',
          snapshot: {
            ...dynamicEditorSnapshot(task, 7),
            'status': 'future',
            'schedule': '2030-01-02 09:02:03',
          },
        );
        final scheduled = store.task(text(task['id']))!;
        expect(scheduled['desired_status'], 'future');
        expect(scheduled['schedule'], '2030-01-02 09:02:03');
        expect(dynamicEditorSnapshot(scheduled, 7)['status'], 'future');
        store.markSubmitted(text(task['id']), postId: 88, status: 'publish');
        final published = store.task(text(task['id']))!;
        expect(published['desired_status'], 'publish');
        expect(published['schedule'], isEmpty);
      },
    );
    test('deleting a task clears conversation and its memories', () {
      final task = ready();
      store.saveTask(task);
      store.addMessage(text(task['id']), 'user', '记录');
      store.markSubmitted(text(task['id']), postId: 9, status: 'pending');
      store.deleteTask(text(task['id']));
      expect(store.task(text(task['id'])), isNull);
      expect(store.messages(text(task['id'])), isEmpty);
      expect(store.search('Original title'), isEmpty);
    });
    test('account files stay isolated and survive restart', () async {
      final directory = await Directory.systemTemp.createTemp(
        'xingyu-dynamic-test-',
      );
      final first = await DynamicTemplateStore.open(1, directory: directory);
      final second = await DynamicTemplateStore.open(2, directory: directory);
      try {
        final task = ready();
        first.saveTask(task);
        expect(second.tasks, isEmpty);
        first.close();
        final reopened = await DynamicTemplateStore.open(
          1,
          directory: directory,
        );
        try {
          expect(reopened.tasks.single['id'], task['id']);
        } finally {
          reopened.close();
        }
      } finally {
        first.close();
        second.close();
        await directory.delete(recursive: true);
      }
    });
  });
}
