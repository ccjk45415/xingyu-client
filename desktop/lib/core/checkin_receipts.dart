import 'dart:async';

import 'api.dart';
import 'platform.dart';
import 'state.dart';

String checkinClientLabel(String client) => switch (client) {
  'android' => 'Android 客户端',
  'windows' => 'Windows 客户端',
  'macos' => 'macOS 客户端',
  'cloud' => '云端服务',
  _ => '来源未确认',
};
String checkinMethodLabel(String method) => switch (method) {
  'manual' => '手动签到',
  'open' => '打开应用自动签到',
  'background' => '后台自动签到',
  'cloud' => '云端自动签到',
  _ => '签到方式未确认',
};
Json? checkinReceipt(dynamic raw, {DateTime? now}) {
  final value = object(raw), time = DateTime.tryParse(text(value['time']));
  final current = now ?? DateTime.now();
  if (time == null ||
      time.isAfter(current.add(const Duration(minutes: 1))) ||
      time.isBefore(current.subtract(const Duration(days: 14)))) {
    return null;
  }
  final client = text(value['client']), method = text(value['method']);
  if (!(client == 'cloud' && method == 'cloud' ||
      ['android', 'windows', 'macos'].contains(client) &&
          ['manual', 'open', 'background'].contains(method))) {
    return null;
  }
  final day =
      time.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
  return {
    'key': 'checkin:$day',
    'time': time.toUtc().toIso8601String(),
    'client': client,
    'method': method,
  };
}

/// Account-scoped metadata only. Reports are authenticated and never contain a
/// website session. A receipt requires a successful POST and fresh signed state.
class CheckinReceipts {
  final AppState app;
  CheckinReceipts(this.app);
  Future<List<Json>>? _flight;
  String _owner = '';
  Json get _data => object(object(app.local['checkinReceipts'])['${app.uid}']);
  List<Json> get events => rows(_data['events']);
  Set<String> get pending =>
      (_data['pending'] is List ? _data['pending'] as List : [])
          .whereType<String>()
          .toSet();
  void _store(List<Json> values, Set<String> outbox) {
    values.sort((a, b) => text(b['time']).compareTo(text(a['time'])));
    final bounded = values.take(14).toList();
    final keys = bounded.map((v) => text(v['key'])).toSet();
    final all = object(app.local['checkinReceipts']);
    all['${app.uid}'] = {
      ..._data,
      'events': bounded,
      'pending': outbox.where(keys.contains).take(10).toList(),
    };
    app.local['checkinReceipts'] = all;
  }

  Future<void> accept(Json raw, {bool upload = true}) async {
    final event = checkinReceipt(raw);
    if (event == null || app.uid <= 0) return;
    final values = events;
    if (values.any((v) => v['key'] == event['key'])) return;
    final outbox = pending;
    if (upload) outbox.add(text(event['key']));
    values.add(event);
    _store(values, outbox);
    app.notices.acceptCheckin(event);
    await app.persist();
  }

  Future<void> record(String source) async => accept({
    'time': DateTime.now().toUtc().toIso8601String(),
    'client': isAndroid
        ? 'android'
        : isMacOS
        ? 'macos'
        : 'windows',
    'method': source,
  });
  Future<List<Json>> sync() {
    final owner = '${app.uid}:${app.generation}';
    if (_flight != null && _owner == owner) return _flight!;
    _owner = owner;
    late final Future<List<Json>> flight;
    flight = _sync().whenComplete(() {
      if (identical(flight, _flight)) _flight = null;
    });
    return _flight = flight;
  }

  Future<List<Json>> _sync() async {
    final uid = app.uid, generation = app.generation;
    bool current() => app.uid == uid && app.generation == generation;
    if (uid <= 0) return [];
    if (isAndroid) {
      try {
        final status = object(
          await platformChannel.invokeMethod('checkinBackgroundStatus'),
        );
        if (current() && number(status['uid']) == uid) {
          for (final event in rows(status['events'])) {
            await accept(event);
          }
        }
      } catch (_) {}
    }
    if (!current()) return [];
    final token = app.verified ? app.token : await app.checkin.cloudToken();
    if (!current()) return [];
    if (token.isEmpty) return events;
    final outbox = pending;
    final batch = events
        .where((v) => outbox.contains(v['key']))
        .where(
          (v) =>
              DateTime.tryParse(text(v['time']))
                  ?.isAfter(DateTime.now().subtract(const Duration(days: 7))) ==
              true,
        )
        .take(10)
        .toList();
    if (batch.isNotEmpty) {
      await app.service.request(
        '/checkin/v1/events',
        token: token,
        body: {
          'events': batch
              .map(
                (v) => {
                  'time': v['time'],
                  'client': v['client'],
                  'method': v['method'],
                },
              )
              .toList(),
        },
      );
      if (!current()) return [];
      final left = pending..removeAll(batch.map((v) => text(v['key'])));
      _store(events, left);
      await app.persist();
    }
    final response = await app.service.request(
      '/checkin/v1/events',
      token: token,
    );
    if (!current()) return [];
    final values = events;
    for (final value in rows(response['events'])) {
      final receipt = checkinReceipt(value);
      if (receipt == null) continue;
      if (value['read'] == true) {
        app.notices.readSync.confirm([text(receipt['key'])], website: false);
      }
      values.removeWhere((v) => v['key'] == receipt['key']);
      values.add(receipt);
    }
    _store(values, pending);
    await app.persist();
    return events;
  }

  Future<void> syncReads() async {
    final uid = app.uid, generation = app.generation;
    if (uid <= 0) return;
    final sent = (_data['read_sent'] is List ? _data['read_sent'] as List : [])
        .whereType<String>()
        .toSet();
    final keys = events
        .map((v) => text(v['key']))
        .where(
          (key) => app.notices.readSync.contains(key) && !sent.contains(key),
        )
        .toList();
    if (keys.isEmpty) return;
    final token = app.verified ? app.token : await app.checkin.cloudToken();
    if (token.isEmpty || app.uid != uid || app.generation != generation) return;
    await app.service.request(
      '/checkin/v1/events/read',
      token: token,
      body: {'keys': keys},
    );
    if (app.uid != uid || app.generation != generation) return;
    sent.addAll(keys);
    final all = object(app.local['checkinReceipts']);
    all['$uid'] = {
      ..._data,
      'read_sent': sent.toList().reversed.take(30).toList().reversed.toList(),
    };
    app.local['checkinReceipts'] = all;
    await app.persist();
  }
}
