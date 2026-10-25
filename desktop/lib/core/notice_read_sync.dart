import 'api.dart';
import 'state.dart';

bool validNoticeKey(String key) => RegExp(
  r'^(?:dm:[1-9][0-9]{0,15}|chat:[12]:[1-9][0-9]{0,15}|(?:reply|vote):[A-Za-z0-9_-]{1,100})$',
).hasMatch(key);

/// Only notification identifiers are stored/synchronized. Read receipts are
/// separate from seen/poll cursors: fetching a message never acknowledges it.
class NoticeReadSync {
  final AppState app;
  final void Function(Set<String>) apply;
  NoticeReadSync(this.app, this.apply);
  Future<void>? _flight;
  String _owner = '';
  Json get _data => object(object(app.local['noticeReadSync'])['${app.uid}']);
  Set<String> _keys(String field) =>
      (_data[field] is List ? _data[field] as List : [])
          .whereType<String>()
          .where(validNoticeKey)
          .toSet();
  bool contains(String key) => _keys('read').contains(key);
  void _store(Json data) {
    final all = object(app.local['noticeReadSync']);
    all['${app.uid}'] = data;
    app.local['noticeReadSync'] = all;
  }

  void _bounded(Set<String> keys) {
    while (keys.length > 512) {
      keys.remove(keys.first);
    }
  }

  void confirm(Iterable<String> values, {bool website = true}) {
    if (app.uid <= 0) return;
    final data = _data,
        read = _keys('read'),
        pending = _keys('pending'),
        site = _keys('site');
    final keys = values.where(validNoticeKey).toSet()..removeAll(read);
    if (keys.isEmpty) {
      apply(read);
      return;
    }
    read.addAll(keys);
    pending.addAll(keys);
    if (website) {
      site.addAll(
        keys.where(
          (key) => key.startsWith('reply:') || key.startsWith('vote:'),
        ),
      );
    }
    for (final set in [read, pending, site]) {
      _bounded(set);
    }
    _store({
      ...data,
      'read': read.toList(),
      'pending': pending.toList(),
      'site': site.toList(),
    });
    apply(read);
  }

  Future<void> sync() {
    final owner = '${app.uid}:${app.generation}';
    if (_flight != null && _owner == owner) return _flight!;
    _owner = owner;
    late final Future<void> flight;
    flight = _sync().whenComplete(() {
      if (identical(_flight, flight)) _flight = null;
    });
    return _flight = flight;
  }

  Future<void> _sync() async {
    if (app.uid <= 0) return;
    final uid = app.uid, generation = app.generation;
    Object? siteError;
    bool current() => app.uid == uid && app.generation == generation;
    // Website notifications retain their official read state even when the user
    // has not enrolled the independent chat identity.
    for (final source in ['reply', 'vote']) {
      final batch = _keys('site')
          .where((key) => key.startsWith('$source:'))
          .take(30)
          .toSet();
      if (batch.isEmpty) continue;
      try {
        await app.site.post('user/makeNotificationAsRead', {
          'ids': batch.map((key) => key.substring(source.length + 1)).toList(),
          'action': source,
        });
      } catch (error) {
        siteError = error;
        if (!current()) return;
        continue;
      }
      if (!current()) return;
      final data = _data, remaining = _keys('site')..removeAll(batch);
      _store({...data, 'site': remaining.toList()});
    }
    if (!app.verified) {
      if (siteError != null) throw siteError;
      return;
    }
    final pending = _keys('pending').take(60).toSet();
    if (pending.isNotEmpty) {
      await app.social('/dm/v1/notice-reads', body: {'keys': pending.toList()});
      if (!current()) return;
      final data = _data, left = _keys('pending')..removeAll(pending);
      _store({...data, 'pending': left.toList()});
    }
    final response = await app.social('/dm/v1/notice-reads');
    if (!current()) return;
    final remote = (response['keys'] is List ? response['keys'] as List : [])
        .whereType<String>()
        .where(validNoticeKey);
    final read = _keys('read')..addAll(remote);
    _bounded(read);
    _store({..._data, 'read': read.toList()});
    apply(read);
    if (siteError != null) throw siteError;
  }
}
