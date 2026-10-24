import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' show parseFragment;

import 'api.dart';
import 'platform.dart';
import 'system_notices.dart';
import 'state.dart';

class AppNotice {
  final String key, kind, title, preview, channel;
  final int target;
  final DateTime time;
  bool read = false;
  AppNotice({
    required this.key,
    required this.kind,
    required this.title,
    required this.preview,
    required this.target,
    this.channel = '',
  }) : time = DateTime.now();
}

/// Foreground-only reminders. No native notification permission, background
/// service, website read-state mutation, or message body persisted to disk.
class InAppNotices extends ChangeNotifier {
  final AppState app;
  final system = SystemNotices();
  Json systemStatus = {};
  AppNotice? opened;
  InAppNotices(this.app) {
    system.onOpen = () => unawaited(syncSystem());
  }
  final List<AppNotice> entries = [];
  final Set<String> _failed = {};
  final Map<String, ({int after, int before, int newest})> _chatBacklogs = {};
  Timer? _timer;
  bool _foreground = true, _disposed = false;
  int _epoch = 0, _flight = -1;
  String route = '', channel = '1';
  int routeId = 0;
  DateTime? checkedAt;
  AppNotice? banner;

  Json get preferences =>
      object(object(app.local['inAppNoticePrefs'])['${app.uid}']);
  bool enabled(String key) => preferences[key] != false;
  bool get enabledAll => enabled('enabled');
  bool get systemEnabled => preferences['system'] == true && enabledAll;
  bool get _canPoll => _foreground || systemEnabled && !isAndroid;
  bool get showPreview => preferences['preview'] == true;
  int get unread => entries.where((entry) => !entry.read).length;
  String get status => !enabledAll
      ? '应用内提醒已关闭'
      : !_foreground
      ? systemEnabled
            ? (isAndroid ? '由系统安排后台检查' : '正在后台接收新消息')
            : '应用在后台时暂停检查'
      : _failed.isNotEmpty
      ? '部分提醒暂未同步，将在联网后重试'
      : checkedAt == null
      ? '打开应用后同步新消息'
      : '应用使用期间约每 30 秒检查新消息';

  void changed() {
    if (!_disposed) notifyListeners();
  }

  void start() {
    if (_disposed) return;
    _foreground = true;
    unawaited(syncSystem());
    _timer?.cancel();
    // Keep notification requests away from the first page's startup requests.
    _timer = Timer(const Duration(seconds: 2), () {
      unawaited(refresh());
      _timer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(refresh()),
      );
    });
  }

  void pause({bool notify = true}) {
    _foreground = false;
    _epoch++;
    if (!systemEnabled || isAndroid) _timer?.cancel();
    banner = null;
    if (notify) changed();
  }

  void clear() {
    _epoch++;
    entries.clear();
    _failed.clear();
    _chatBacklogs.clear();
    banner = null;
    opened = null;
    checkedAt = null;
    changed();
  }

  Future<void> setPreference(String key, bool value) async {
    if (!{
      'enabled',
      'dm',
      'chatMention',
      'postReply',
      'commentReply',
      'like',
      'preview',
      'system',
    }.contains(key)) {
      return;
    }
    if (key == 'system' && value) {
      if (isAndroid && !app.site.remember) {
        throw ApiFailure(400, '后台通知需要在登录时勾选保持登录');
      }
      if (!await system.request()) throw ApiFailure(400, '系统通知未授权，可在系统设置中开启');
    }
    final all = object(app.local['inAppNoticePrefs']);
    all['${app.uid}'] = {...preferences, key: value};
    app.local['inAppNoticePrefs'] = all;
    _epoch++; // In-flight responses must honor the previous preference boundary.
    banner = null;
    if (!value && key != 'preview') {
      final state = _state();
      if (key == 'enabled') {
        state.clear();
        _chatBacklogs.clear();
      } else {
        for (final source in _sourcesFor(key)) {
          state.remove(source);
          _chatBacklogs.remove(source);
          _failed.remove(source);
        }
      }
      _storeState(state);
    }
    changed();
    await app.persist();
    await syncSystem();
  }

  Future<void> syncSystem() async {
    try {
      await system.configure(
        app.uid,
        systemEnabled && (!isAndroid || app.site.remember),
        preferences,
        _state(),
      );
      systemStatus = await system.status();
      final payload = await system.takeOpen();
      if (number(payload['uid']) == app.uid && app.uid > 0) {
        opened = AppNotice(
          key: text(payload['key']),
          kind: text(payload['kind']),
          title: '消息提醒',
          preview: '',
          target: number(payload['target']),
          channel: text(payload['channel']),
        );
      }
      changed();
    } catch (_) {
      systemStatus = {'supported': false, 'granted': false};
      changed();
    }
  }

  Future<void> stopSystem() => system.configure(0, false, {});

  List<String> _sourcesFor(String key) => switch (key) {
    'chatMention' => ['chat:1', 'chat:2'],
    'postReply' || 'commentReply' => ['reply'],
    'like' => ['vote'],
    _ => [key],
  };

  Json _state() => object(object(app.local['inAppNoticeSeen'])['${app.uid}']);
  void _storeState(Json state) {
    final all = object(app.local['inAppNoticeSeen']);
    all['${app.uid}'] = state;
    app.local['inAppNoticeSeen'] = all;
  }

  bool _valid(int owner, int generation, int epoch) =>
      !_disposed &&
      _canPoll &&
      enabledAll &&
      app.uid == owner &&
      owner > 0 &&
      app.generation == generation &&
      _epoch == epoch;

  bool _visible(AppNotice notice) => switch (notice.kind) {
    'dm' => route == 'dm' && routeId == notice.target,
    'chatMention' => route == 'chat' && channel == notice.channel,
    _ => route == 'notifications' || route == 'noticeCenter',
  };

  void _add(AppNotice notice) {
    if (!enabledAll ||
        !enabled(notice.kind) ||
        entries.any((n) => n.key == notice.key)) {
      return;
    }
    if (_foreground && _visible(notice)) notice.read = true;
    entries.insert(0, notice);
    if (entries.length > 60) entries.removeRange(60, entries.length);
    if (!notice.read && _foreground) banner = notice;
    if (!notice.read && !_foreground && systemEnabled) {
      unawaited(
        system
            .show({
              'uid': app.uid,
              'key': notice.key,
              'kind': notice.kind,
              'title': showPreview ? notice.title : '星屿 · 新消息',
              'body': showPreview ? notice.preview : '你有一条新的消息，点击查看',
              'target': notice.target,
              'channel': notice.channel,
            })
            .catchError((_) {}),
      );
    }
  }

  static String preview(String value) {
    final plain = (parseFragment(value).text ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return String.fromCharCodes(plain.runes.take(100));
  }

  /// The current room's existing socket delivers mentions without waiting for a
  /// poll. Other rooms and private messages use bounded foreground checks.
  void acceptChat(Json message, String selected) {
    if (_disposed ||
        !_canPoll ||
        !enabledAll ||
        !enabled('chatMention') ||
        !app.verified) {
      return;
    }
    final state = _state(), source = 'chat:$selected';
    final id = number(message['id']);
    if (id <= number(state[source])) return;
    state[source] = id;
    _storeState(state);
    _chatNotice(message, selected);
    changed();
    unawaited(app.persist());
  }

  void _chatNotice(Json message, String selected) {
    final sender = object(message['sender']);
    if (number(sender['id']) == app.uid) return;
    final tagged = rows(message['mentions'])
        .any((u) => number(u['id']) == app.uid);
    final replied =
        number(object(object(message['reply_to'])['sender'])['id']) == app.uid;
    if (!tagged && !replied) return;
    _add(
      AppNotice(
        key: 'chat:$selected:${message['id']}',
        kind: 'chatMention',
        title:
            '${text(sender['nickname'], '仓库用户')} 在频道${selected == '1' ? '一' : '二'}${tagged ? '艾特' : '回复'}了你',
        preview: preview(text(message['text'], '[图片]')),
        target: 0,
        channel: selected,
      ),
    );
  }

  Future<Json> _chatBatch(String selected) async {
    final source = 'chat:$selected', state = _state();
    final owner = app.uid, generation = app.generation, epoch = _epoch;
    if (!state.containsKey(source)) {
      return app.social('/v1/channels/$selected/messages?limit=30');
    }
    final after = number(state[source]);
    final pending = _chatBacklogs[source];
    var before = pending?.after == after ? pending!.before : 0;
    var newest = pending?.after == after ? pending!.newest : after;
    var more = false;
    final messages = <Json>[];
    // Drain busy rooms over bounded batches, rather than skipping messages when
    // more than one page arrived. Keeps combined polling below the read budget.
    for (var page = 0; page < 3; page++) {
      final result = await app.social(
        '/v1/channels/$selected/messages?limit=30&after=$after${before > 0 ? '&before=$before' : ''}',
      );
      if (!_valid(owner, generation, epoch)) throw ApiFailure(409, '提醒任务已失效');
      final batch = rows(result['messages']);
      messages.addAll(batch);
      for (final message in batch) {
        final id = number(message['id']);
        if (id > newest) newest = id;
      }
      more = result['has_older'] == true && batch.isNotEmpty;
      if (!more) break;
      before = batch
          .map((m) => number(m['id']))
          .reduce((a, b) => a < b ? a : b);
    }
    return {
      'messages': messages,
      '_after': after,
      '_newest': newest,
      if (more) '_before': before,
    };
  }

  Future<void> refresh() async {
    if (_disposed ||
        !_canPoll ||
        !enabledAll ||
        app.uid <= 0 ||
        _flight == _epoch) {
      return;
    }
    final owner = app.uid, generation = app.generation, epoch = _epoch;
    _flight = epoch;
    Future<void> source(
      String name,
      Future<Json> Function() fetch,
      void Function(Json, Json) consume,
    ) async {
      try {
        final result = await fetch();
        if (!_valid(owner, generation, epoch)) return;
        final state = _state();
        consume(result, state);
        _storeState(state);
        _failed.remove(name);
      } catch (_) {
        if (_valid(owner, generation, epoch)) _failed.add(name);
      }
    }

    try {
      await Future.wait([
        if (enabled('postReply') || enabled('commentReply'))
          source(
            'reply',
            () => app.get('user/notification', {
              'action': 'reply',
              'page': 1,
              'per_page': 30,
              'include': 'user,causer,subject',
              'with[0]': 'user',
              'with[1]': 'causer',
              'with[2]': 'subject',
            }),
            (result, state) => _siteNotices(result, state, 'reply'),
          ),
        if (enabled('like'))
          source(
            'vote',
            () => app.get('user/notification', {
              'action': 'vote',
              'page': 1,
              'per_page': 30,
              'include': 'user,causer,subject',
              'with[0]': 'user',
              'with[1]': 'causer',
              'with[2]': 'subject',
            }),
            (result, state) => _siteNotices(result, state, 'vote'),
          ),
        if (app.verified && enabled('dm'))
          source('dm', () => app.social('/dm/v1/conversations'), (
            result,
            state,
          ) {
            final previous = object(state['dm']);
            final first = !state.containsKey('dm');
            for (final row in rows(result['conversations']).reversed) {
              final peer = object(row['peer']),
                  message = object(row['last_message']);
              final id = number(message['id']), peerId = number(peer['id']);
              if (!first &&
                  id > number(previous['$peerId']) &&
                  number(row['unread']) > 0 &&
                  number(message['sender_id']) != owner) {
                _add(
                  AppNotice(
                    key: 'dm:$id',
                    kind: 'dm',
                    target: peerId,
                    title: '${text(peer['nickname'], '仓库用户')} 发来私信',
                    preview: preview(text(message['text'], '[图片]')),
                  ),
                );
              }
              if (id > number(previous['$peerId'])) {
                previous.remove('$peerId');
                previous['$peerId'] = id;
              }
            }
            // At most 200 conversation cursors; no message content is stored.
            while (previous.length > 200) {
              previous.remove(previous.keys.first);
            }
            state['dm'] = previous;
          }),
        if (app.verified && enabled('chatMention'))
          for (final selected in ['1', '2'])
            source('chat:$selected', () => _chatBatch(selected), (
              result,
              state,
            ) {
              final source = 'chat:$selected',
                  first = !state.containsKey('chat:$selected');
              var last = number(state[source]);
              final messages = rows(result['messages'])
                ..sort((a, b) => number(a['id']).compareTo(number(b['id'])));
              for (final message in messages) {
                final id = number(message['id']);
                if (!first && id > last) _chatNotice(message, selected);
                if (id > last) last = id;
              }
              if (number(result['_before']) > 0) {
                _chatBacklogs[source] = (
                  after: number(result['_after']),
                  before: number(result['_before']),
                  newest: number(result['_newest']),
                );
              } else {
                _chatBacklogs.remove(source);
                state[source] = last > number(result['_newest'])
                    ? last
                    : number(result['_newest']);
              }
            }),
      ]);
      if (_valid(owner, generation, epoch)) {
        checkedAt = DateTime.now();
        changed();
        await app.persist();
      }
    } finally {
      if (_flight == epoch) _flight = -1;
    }
  }

  void _siteNotices(Json result, Json state, String source) {
    final first = !state.containsKey(source);
    final seen = (state[source] is List ? state[source] as List : [])
        .whereType<String>()
        .toSet();
    for (final row in rows(result['data']).reversed) {
      final id = text(row['id']);
      if (id.isEmpty) continue;
      if (!first && !seen.contains(id) && row['read_at'] == null) {
        final subject = object(row['subject']), actor = object(row['user']);
        final isPost = row['subject_type'] == 'post';
        final kind = source == 'vote'
            ? 'like'
            : isPost
            ? 'postReply'
            : 'commentReply';
        _add(
          AppNotice(
            key: '$source:$id',
            kind: kind,
            title:
                '${text(actor['nickname'], '仓库用户')}${source == 'vote' ? '赞了' : '回复了'}你的${isPost ? '帖子' : '评论'}',
            preview: preview(
              text(
                object(row['causer'])['content'],
                text(subject['title'], text(subject['content'])),
              ),
            ),
            target: isPost ? number(subject['id']) : number(subject['post_id']),
          ),
        );
      }
      seen.add(id);
    }
    state[source] = seen.toList().reversed.take(200).toList().reversed.toList();
  }

  void read(AppNotice notice) {
    notice.read = true;
    if (identical(banner, notice)) banner = null;
    changed();
  }

  void readAll() {
    for (final notice in entries) {
      notice.read = true;
    }
    banner = null;
    changed();
  }

  void dismiss() {
    banner = null;
    changed();
  }

  @override
  void dispose() {
    _disposed = true;
    system.onOpen = null;
    _epoch++;
    _timer?.cancel();
    super.dispose();
  }
}
