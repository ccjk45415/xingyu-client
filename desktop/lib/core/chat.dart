import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'state.dart';

class ChatRoom {
  final SplayTreeMap<int, Json> messages = SplayTreeMap();
  String draft = '';
  Json? image, reply, pending;
  bool sending = false,
      older = false,
      loading = false,
      historyLoaded = false,
      historyFailed = false;
  final Map<int, String> mentions = {};
}

class ChatController extends ChangeNotifier {
  final AppState app;
  final rooms = {'1': ChatRoom(), '2': ChatRoom()};
  final Map<int, Json> profiles = {};
  String channel = '1', status = '连接后开始聊天';
  WebSocket? socket;
  late final connector = app.socketFactory();
  Timer? _heartbeat, _retry, _confirmation;
  int _generation = 0, _failures = 0;
  bool active = false, ready = false, connecting = false, _disposed = false;
  ChatController(this.app);
  ChatRoom get room => rooms[channel]!;
  void update() {
    if (!_disposed) notifyListeners();
  }

  Json profile(Json original) => profiles[number(original['id'])] ?? original;
  Future<void> start({bool reconnect = false}) async {
    if (!reconnect && active && (ready || connecting)) return;
    active = true;
    if (app.verified) await _connect();
  }

  void pause() {
    active = false;
    _detach();
  }

  void _detach() {
    connector.cancel();
    _generation++;
    ready = false;
    connecting = false;
    _heartbeat?.cancel();
    _retry?.cancel();
    _confirmation?.cancel();
    for (final room in rooms.values) {
      room.sending = false;
      room.loading = false;
    }
    final old = socket;
    socket = null;
    if (old != null) unawaited(old.close());
  }

  Future<void> choose(String next) async {
    if (next == channel || !rooms.containsKey(next)) return;
    _detach();
    channel = next;
    update();
    if (active) await _connect();
  }

  bool _valid(int request, String selected, int owner) =>
      !_disposed &&
      active &&
      request == _generation &&
      selected == channel &&
      owner == app.uid;
  Future<void> _connect() async {
    if (!active || !app.verified || _disposed) return;
    _detach();
    final request = _generation,
        selected = channel,
        owner = app.uid,
        token = app.token;
    connecting = true;
    unawaited(_history(request, selected, owner, token));
    unawaited(_syncProfile(request, selected, owner));
    status = '正在连接频道${selected == '1' ? '一' : '二'}…';
    update();
    try {
      final ws = await connector.connect(
        '${app.service.origin.replaceFirst('https:', 'wss:').replaceFirst('http:', 'ws:')}/ws?channel=$selected',
        headers: {'Authorization': 'Bearer $token'},
      );
      if (!_valid(request, selected, owner)) {
        unawaited(ws.close());
        return;
      }
      socket = ws;
      ws.listen(
        (raw) {
          if (!_valid(request, selected, owner) || raw == 'pong') return;
          try {
            final event = object(jsonDecode(raw as String));
            if (event['channel'] != selected) return;
            switch (event['type']) {
              case 'ready':
                ready = true;
                connecting = false;
                _failures = 0;
                final user = object(event['user']);
                profiles[number(user['id'])] = user;
                status = '已连接 · 仓库认证 · UID $owner';
              case 'profile':
                final user = object(event['user']);
                profiles[number(user['id'])] = user;
              case 'message':
                _merge(rooms[selected]!, event);
              case 'error':
                final target = rooms[selected]!;
                target.sending = false;
                status = text(event['error'], '发送失败，请重试');
            }
            update();
          } catch (_) {
            status = '收到的消息格式异常';
            update();
          }
        },
        onError: (Object e) {
          if (_valid(request, selected, owner)) {
            _reconnect(request, selected, owner);
          }
        },
        onDone: () {
          if (!_valid(request, selected, owner)) return;
          if (ws.closeCode == 4003) {
            status = '仓库认证已过期，请重新认证';
            ready = false;
            app.expireIdentity();
            update();
            return;
          }
          if (ws.closeCode == 4001) {
            status = '此账号已在另一个客户端进入，点击重连可切回';
            ready = false;
            update();
            return;
          }
          _reconnect(request, selected, owner);
        },
      );
      _heartbeat = Timer.periodic(const Duration(seconds: 35), (_) {
        if (_valid(request, selected, owner)) ws.add('ping');
      });
    } catch (e) {
      if (!_valid(request, selected, owner)) return;
      if (e is ApiFailure && [401, 403].contains(e.status)) {
        ready = false;
        app.expireIdentity();
        status = '仓库认证已过期，请重新认证';
        update();
        return;
      }
      status = '$e';
      update();
      _reconnect(request, selected, owner);
    }
  }

  Future<void> _syncProfile(int request, String selected, int owner) async {
    try {
      await app.syncProfile();
      if (!_valid(request, selected, owner)) return;
      final latest = object(app.identity?['user']);
      if (number(latest['id']) == owner) profiles[owner] = latest;
      update();
    } catch (_) {
      /* Existing verification remains usable while the website is unavailable. */
    }
  }

  Future<void> _history(
    int request,
    String selected,
    int owner,
    String token,
  ) async {
    final target = rooms[selected]!;
    target.historyFailed = false;
    try {
      final result = await app.service.request(
        '/v1/channels/$selected/messages?limit=30',
        token: token,
      );
      if (!_valid(request, selected, owner)) return;
      _merge(target, result);
      target.historyLoaded = true;
      update();
    } catch (error) {
      if (!_valid(request, selected, owner)) return;
      target.historyFailed = true;
      if (error is ApiFailure && [401, 403].contains(error.status)) {
        ready = false;
        app.expireIdentity();
      }
      update();
    }
  }

  Future<void> retryHistory() =>
      _history(_generation, channel, app.uid, app.token);

  void _reconnect(int request, String selected, int owner) {
    if (!_valid(request, selected, owner) || _retry?.isActive == true) return;
    ready = false;
    connecting = false;
    room.sending = false;
    status = '连接断开，正在重连…';
    update();
    final delay = (1 << _failures.clamp(0, 4));
    _failures++;
    _retry = Timer(Duration(seconds: delay), () {
      if (_valid(request, selected, owner)) unawaited(_connect());
    });
  }

  void _merge(ChatRoom target, Json event) {
    for (final message in rows(event['messages'])) {
      if (message['channel'] != channel) continue;
      target.messages[number(message['id'])] = message;
      final pending = target.pending;
      if (number(object(message['sender'])['id']) == app.uid &&
          pending != null &&
          message['client_id'] == pending['client_id']) {
        if (target.draft.trim() == pending['text']) {
          target.draft = '';
          target.mentions.clear();
        }
        if (target.image?['id'] == pending['image_id']) target.image = null;
        if (target.reply?['id'] == pending['reply_to_id']) target.reply = null;
        target.pending = null;
        target.sending = false;
        _confirmation?.cancel();
      }
    }
    if (event.containsKey('has_older')) {
      target.older = event['has_older'] == true;
    }
    while (target.messages.length > 300) {
      target.messages.remove(target.messages.firstKey());
    }
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    target.messages.removeWhere(
      (key, message) =>
          DateTime.tryParse(text(message['created_at']))?.isBefore(cutoff) ==
          true,
    );
  }

  Future<void> older() async {
    final target = room,
        request = _generation,
        selected = channel,
        owner = app.uid;
    if (!ready ||
        target.loading ||
        !target.older ||
        target.messages.isEmpty ||
        target.messages.length >= 300) {
      return;
    }
    target.loading = true;
    update();
    try {
      final r = await app.service.request(
        '/v1/channels/$selected/messages?before=${target.messages.firstKey()}&limit=${(300 - target.messages.length).clamp(1, 30)}',
        token: app.token,
      );
      if (_valid(request, selected, owner)) _merge(target, r);
    } finally {
      if (_valid(request, selected, owner)) {
        target.loading = false;
        update();
      }
    }
  }

  void send() {
    if (!ready || room.sending || socket == null) return;
    final target = room;
    if (target.pending == null) {
      if (target.draft.trim().isEmpty && target.image == null) return;
      if (target.draft.trim().runes.length > 300) {
        status = '每条消息最多300字';
        update();
        return;
      }
      target.pending = {
        'type': 'send',
        'channel': channel,
        'text': target.draft.trim(),
        'client_id': nonce(),
        'image_id': target.image?['id'],
        'reply_to_id': target.reply?['id'] ?? 0,
        'mentions': target.mentions.keys
            .where((id) => target.draft.contains('(UID:$id)'))
            .toList(),
      };
    }
    target.sending = true;
    socket!.add(jsonEncode(target.pending));
    _confirmation?.cancel();
    final pending = target.pending;
    _confirmation = Timer(const Duration(seconds: 12), () {
      if (!_disposed && target.pending == pending) {
        target.sending = false;
        status = '未收到确认，可重试同一条消息';
        update();
      }
    });
    update();
  }

  @override
  void dispose() {
    _disposed = true;
    active = false;
    _detach();
    super.dispose();
  }
}
