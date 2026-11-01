import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'api.dart';
import 'dynamic_templates.dart';

/// One private local database per website account. Conversations are retained;
/// only curated template/task summaries enter the full-text index.
class DynamicTemplateStore {
  final int uid;
  final Database db;
  bool _closed = false;
  DynamicTemplateStore(this.uid, this.db) {
    if (uid <= 0) throw ArgumentError('需要已登录账号');
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('PRAGMA journal_mode = WAL');
    db.execute(
      'CREATE TABLE IF NOT EXISTS templates (id TEXT NOT NULL, version INTEGER NOT NULL, body TEXT NOT NULL, updated TEXT NOT NULL, PRIMARY KEY(id,version))',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, body TEXT NOT NULL, updated TEXT NOT NULL)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS messages (seq INTEGER PRIMARY KEY AUTOINCREMENT, task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE, role TEXT NOT NULL, content TEXT NOT NULL, created TEXT NOT NULL)',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS task_messages ON messages(task_id,seq)',
    );
    db.execute(
      'CREATE TABLE IF NOT EXISTS memories (id TEXT PRIMARY KEY, task_id TEXT, kind TEXT NOT NULL, title TEXT NOT NULL, content TEXT NOT NULL, updated TEXT NOT NULL)',
    );
    db.execute(
      "CREATE VIRTUAL TABLE IF NOT EXISTS memory_search USING fts5(id UNINDEXED, title, content, tokenize='trigram')",
    );
    for (final template in starterDynamicTemplates()) {
      if (db.select('SELECT id FROM templates WHERE id = ? LIMIT 1', [
        template.id,
      ]).isEmpty) {
        saveTemplate(template);
      }
    }
    db.execute('PRAGMA user_version = 1');
  }
  static Future<DynamicTemplateStore> open(
    int uid, {
    Directory? directory,
  }) async {
    if (uid <= 0) throw ArgumentError('需要已登录账号');
    final root = directory ?? await getApplicationSupportDirectory();
    final folder = Directory('${root.path}/dynamic-templates');
    await folder.create(recursive: true);
    return DynamicTemplateStore(
      uid,
      sqlite3.open('${folder.path}/account-$uid.sqlite'),
    );
  }

  List<DynamicTemplate> get templates => db
      .select(
        'SELECT body FROM templates t WHERE version = (SELECT MAX(version) FROM templates v WHERE v.id=t.id) ORDER BY updated DESC',
      )
      .map((r) => DynamicTemplate(object(jsonDecode(r['body'] as String))))
      .toList();
  List<Json> get tasks => db
      .select('SELECT body FROM tasks ORDER BY updated DESC')
      .map((r) => object(jsonDecode(r['body'] as String)))
      .toList();
  Json? task(String id) {
    final result = db.select('SELECT body FROM tasks WHERE id=?', [id]);
    return result.isEmpty
        ? null
        : object(jsonDecode(result.first['body'] as String));
  }

  List<Json> versions(String id) => db
      .select('SELECT body FROM templates WHERE id=? ORDER BY version DESC', [
        id,
      ])
      .map((r) => object(jsonDecode(r['body'] as String)))
      .toList();
  DynamicTemplate saveTemplate(DynamicTemplate value) {
    final found = db.select(
      'SELECT MAX(version) AS version FROM templates WHERE id=?',
      [value.id],
    );
    final existing = number(found.first['version']);
    final template = DynamicTemplate({...value.data, 'version': existing + 1});
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute(
      'INSERT INTO templates(id,version,body,updated) VALUES(?,?,?,?)',
      [template.id, template.version, jsonEncode(template.data), now],
    );
    putMemory(
      'template.${template.id}',
      kind: 'template',
      title: template.name,
      content:
          '${aiTypesLabel(template.kind)} ${text(template.data['aliases'])}\n${text(template.data['notes'])}\n模板版本 ${template.version}',
    );
    return template;
  }

  void deleteTemplate(String id) {
    db.execute('DELETE FROM templates WHERE id=?', [id]);
    deleteMemory('template.$id');
  }

  void saveTask(Json task) {
    final id = text(task['id']);
    if (id.isEmpty) throw const FormatException('任务编号缺失');
    task['updated_at'] = DateTime.now().toUtc().toIso8601String();
    db.execute(
      'INSERT INTO tasks(id,body,updated) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET body=excluded.body,updated=excluded.updated',
      [id, jsonEncode(task), task['updated_at']],
    );
  }

  void addMessage(String taskId, String role, String content) {
    if (!['user', 'assistant', 'tool'].contains(role)) {
      throw ArgumentError('消息类型错误');
    }
    db.execute(
      'INSERT INTO messages(task_id,role,content,created) VALUES(?,?,?,?)',
      [taskId, role, content, DateTime.now().toUtc().toIso8601String()],
    );
  }

  List<Json> messages(String taskId) => db
      .select(
        'SELECT seq,role,content,created FROM messages WHERE task_id=? ORDER BY seq',
        [taskId],
      )
      .map((r) => Map<String, dynamic>.from(r))
      .toList();
  void deleteTask(String id) {
    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute('DELETE FROM tasks WHERE id=?', [id]);
      for (final row in db.select('SELECT id FROM memories WHERE task_id=?', [
        id,
      ])) {
        deleteMemory(row['id'] as String);
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void putMemory(
    String id, {
    required String kind,
    required String title,
    required String content,
    String? taskId,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute(
      'INSERT INTO memories(id,task_id,kind,title,content,updated) VALUES(?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET task_id=excluded.task_id,kind=excluded.kind,title=excluded.title,content=excluded.content,updated=excluded.updated',
      [id, taskId, kind, title, content, now],
    );
    db.execute('DELETE FROM memory_search WHERE id=?', [id]);
    db.execute('INSERT INTO memory_search(id,title,content) VALUES(?,?,?)', [
      id,
      title,
      content,
    ]);
  }

  void deleteMemory(String id) {
    db.execute('DELETE FROM memory_search WHERE id=?', [id]);
    db.execute('DELETE FROM memories WHERE id=?', [id]);
  }

  List<Json> search(String query, {int limit = 20}) {
    final words = query.trim();
    if (words.isEmpty) {
      return db
          .select(
            'SELECT id,task_id,kind,title,content,updated FROM memories ORDER BY updated DESC LIMIT ?',
            [limit.clamp(1, 50)],
          )
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
    }
    // Short CJK names require substring matching; FTS5 trigram requires >=3
    // unicode codepoints. Bound all parameters, including FTS query strings.
    if (words.runes.length < 3) {
      final pattern =
          '%${words.replaceAll('\\', '\\\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
      return db
          .select(
            "SELECT id,task_id,kind,title,content,updated FROM memories WHERE title LIKE ? ESCAPE '\\' OR content LIKE ? ESCAPE '\\' ORDER BY updated DESC LIMIT ?",
            [pattern, pattern, limit.clamp(1, 50)],
          )
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
    }
    final expression = '"${words.replaceAll('"', '""')}"';
    return db
        .select(
          'SELECT m.id,m.task_id,m.kind,m.title,m.content,m.updated FROM memory_search f JOIN memories m ON m.id=f.id WHERE memory_search MATCH ? ORDER BY rank LIMIT ?',
          [expression, limit.clamp(1, 50)],
        )
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
  }

  void markSubmitted(
    String taskId, {
    int postId = 0,
    String status = 'pending',
    Json? snapshot,
  }) {
    final value = task(taskId);
    if (value == null) return;
    if (snapshot != null) {
      value['editor_snapshot'] = snapshot;
      final fields = object(value['fields']);
      fields['title'] = text(snapshot['title']);
      fields['body_html'] = text(snapshot['content']);
      fields['full_body'] = true;
      fields['cover'] = text(snapshot['thumb']);
      fields['tags'] = text(snapshot['tag_text']);
      value['fields'] = fields;
      value['category_ids'] = snapshot['category_ids'] ?? <int>[];
      value['version'] = text(snapshot['version']);
      value['baseline'] = text(snapshot['baseline']);
    }
    value['status'] = status == 'draft' ? 'website_draft' : status;
    // The editor may have changed a template draft into a published or
    // scheduled post. A later revision must keep that confirmed website state.
    value['desired_status'] = switch (status) {
      'draft' || 'publish' || 'future' => status,
      _ => 'pending',
    };
    value['schedule'] = status == 'future'
        ? text(snapshot?['schedule'], text(value['schedule']))
        : '';
    value['post_id'] = postId;
    value['needs_latest'] = true;
    value['submitted_at'] = DateTime.now().toUtc().toIso8601String();
    db.execute('BEGIN IMMEDIATE');
    try {
      saveTask(value);
      addMessage(
        taskId,
        'assistant',
        status == 'draft'
            ? '已保存到官网草稿。'
            : '已提交到官网，当前状态：${dynamicStatusLabel(status)}。',
      );
      if (status != 'draft') {
        putMemory(
          'submission.$taskId',
          kind: 'submission',
          title: text(object(value['fields'])['title']),
          content: dynamicMemorySummary(value, status: status, postId: postId),
          taskId: taskId,
        );
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  String exportTask(String id) =>
      const JsonEncoder.withIndent('  ')
          .convert({'task': task(id), 'messages': messages(id)});
  void close() {
    if (!_closed) {
      _closed = true;
      db.close();
    }
  }
}

String aiTypesLabel(String kind) => switch (kind) {
  'game' => '游戏',
  'asmr' => '音声',
  'comic' => '漫画',
  'animation' => '动画',
  _ => '其他作品',
};
