import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'platform.dart';
import 'state.dart';
import 'error_diagnostics.dart';

Future<void> _refreshCheckinProxy() async {
  // The application installs this transport before loading account state.
  // Clients using a different transport (such as isolated fixtures) own it themselves.
  if (HttpOverrides.current is AndroidProxyOverrides) {
    await refreshSystemProxy();
  }
}

/// Only a fresh account response can establish whether today's check-in exists.
class CheckinController extends ChangeNotifier {
  final AppState app;
  final bool windows;
  final DateTime Function() now;
  final Future<void> Function() refreshProxy;
  CheckinController(
    this.app, {
    bool? windows,
    DateTime Function()? now,
    Future<void> Function()? refreshProxy,
  }) : windows = windows ?? Platform.isWindows,
       now = now ?? DateTime.now,
       refreshProxy = refreshProxy ?? _refreshCheckinProxy;
  bool busy = false, _disposed = false;
  String message = '';
  DateTime _automaticCheck = DateTime(2000);
  Timer? _windowsTimer;
  bool _windowVisible = true, _stopping = false, _automaticPending = false;
  int _failures = 0;
  String _monitorAccount = '', _loginRequiredFor = '';
  bool get _monitorEnabled =>
      windows &&
      app.uid > 0 &&
      !_stopping &&
      !_disposed &&
      app.clientConfig.enabled('checkin') &&
      (backgroundEnabled || _windowVisible && openEnabled) &&
      _loginRequiredFor != '${app.uid}:${app.generation}';
  void setWindowVisible(bool visible) {
    _windowVisible = visible;
    if (!_monitorEnabled) {
      _windowsTimer?.cancel();
      _windowsTimer = null;
    }
  }

  void _scheduleWindows() {
    _windowsTimer?.cancel();
    _windowsTimer = null;
    if (!_monitorEnabled) return;
    final seconds = _failures == 0
        ? 30
        : (15 * (1 << (_failures - 1).clamp(0, 5))).clamp(15, 300);
    _windowsTimer = Timer(
      Duration(seconds: seconds),
      () => unawaited(automatic(force: true)),
    );
  }

  Json cloud = {}, background = {};
  Json get preferences =>
      object(object(app.local['checkinPreferences'])['${app.uid}']);
  Json get latest => object(object(app.local['checkinLatest'])['${app.uid}']);
  bool get signed =>
      app.user?['is_signed'] == true || app.user?['is_signed'] == 1;
  bool get openEnabled => preferences['on_open'] == true;
  bool get backgroundEnabled => preferences['background'] == true;
  String get backgroundStatus {
    final status = text(background['status'], '等待系统调度');
    if (!['今日已签到', 'signed'].contains(status)) return status;
    final time = DateTime.tryParse(text(background['time']));
    if (time == null) return '后台成功记录时间未知，今日待确认';
    final recorded = time.toUtc().add(const Duration(hours: 8));
    final today = now().toUtc().add(const Duration(hours: 8));
    return recorded.year == today.year &&
            recorded.month == today.month &&
            recorded.day == today.day
        ? '今日已签到'
        : '上次后台签到成功，今日待确认';
  }

  void changed() {
    if (!_disposed) notifyListeners();
  }

  bool current(int uid, int generation) =>
      !_disposed && uid == app.uid && generation == app.generation;

  Future<void> setPreference(String key, bool enabled) async {
    if (app.uid <= 0) throw ApiFailure(401, '请先登录');
    if (key == 'background' &&
        enabled &&
        !windows &&
        (!isAndroid || !app.site.remember)) {
      throw ApiFailure(400, '后台签到需要在登录时勾选保持登录');
    }
    final uid = app.uid, generation = app.generation;
    if (key == 'background' && isAndroid) {
      await platformChannel.invokeMethod('configureCheckinBackground', {
        'enabled': enabled,
        'uid': uid,
      });
      if (!current(uid, generation)) return;
    }
    final all = object(app.local['checkinPreferences']);
    all['$uid'] = {...preferences, key: enabled};
    app.local['checkinPreferences'] = all;
    changed();
    await app.persist();
    if (key == 'on_open' || key == 'background') {
      if (enabled) _loginRequiredFor = '';
      unawaited(automatic(force: true));
    }
  }

  Future<void> automatic({bool force = false, Json? freshUser}) async {
    if (_disposed || app.uid <= 0) return;
    final owner = '${app.uid}:${app.generation}';
    if (_monitorAccount != owner) {
      _monitorAccount = owner;
      _failures = 0;
      _stopping = false;
      _loginRequiredFor = '';
      _automaticCheck = DateTime(2000);
    }
    if (_stopping) return;
    if (windows && !_monitorEnabled) {
      _scheduleWindows();
      return;
    }
    if (busy) {
      _automaticPending = true;
      return;
    }
    if (!force &&
        now().difference(_automaticCheck) <
            (windows
                ? const Duration(seconds: 30)
                : const Duration(minutes: 10))) {
      _scheduleWindows();
      return;
    }
    _automaticCheck = now();
    if (isAndroid) {
      try {
        background = object(
          await platformChannel.invokeMethod('checkinBackgroundStatus'),
        );
        // Reconcile the native task with the active account, never reuse another UID.
        await platformChannel.invokeMethod('configureCheckinBackground', {
          'enabled': backgroundEnabled && app.site.remember,
          'uid': app.uid,
        });
      } catch (_) {}
    }
    if ((windows ? _monitorEnabled : openEnabled) &&
        app.clientConfig.enabled('checkin')) {
      try {
        if (windows) {
          // A proxy may be enabled or moved to a new port while the window is in the tray.
          try {
            await refreshProxy();
          } catch (_) {
            /* Keep the last known proxy and retry the request. */
          }
          if (_disposed ||
              _stopping ||
              owner != '${app.uid}:${app.generation}' ||
              !_monitorEnabled) {
            return;
          }
        }
        await run(
          source: windows && !_windowVisible ? 'background' : 'open',
          freshUser: freshUser,
        );
        if (owner == '${app.uid}:${app.generation}') _failures = 0;
      } catch (error, stack) {
        if (owner == '${app.uid}:${app.generation}') {
          _failures++;
          // Only an unauthorized session/identity response establishes login loss.
          // Access blocks, redirects and CSRF expiry can recover without logging in.
          if (error is ApiFailure && error.status == 401) {
            _loginRequiredFor = owner;
            message = '登录已失效，重新登录后继续自动签到';
          } else {
            message = windows ? '暂时无法访问网站，将自动重试签到' : '暂时无法访问网站，回到应用时将再次尝试';
          }
          if (_failures == 1) {
            unawaited(appDiagnostics.record(error, stack, 'automatic-checkin'));
          }
        }
      }
    }
    _scheduleWindows();
    changed();
  }

  Future<Json> account(int uid) async {
    final data = object((await app.site.get('auth/me'))['data']);
    if (number(data['id']) != uid) throw ApiFailure(401, '登录状态已变化，请重新登录');
    return data;
  }

  Future<void> run({String source = 'manual', Json? freshUser}) async {
    if (busy) return;
    final uid = app.uid, generation = app.generation;
    if (uid <= 0) throw ApiFailure(401, '请先登录');
    busy = true;
    message = '正在确认今日签到';
    changed();
    try {
      var user =
          freshUser != null &&
              number(freshUser['id']) == uid &&
              [true, false, 0, 1].contains(freshUser['is_signed'])
          ? Map<String, dynamic>.of(freshUser)
          : await account(uid);
      if (!current(uid, generation)) return;
      final wasUnsigned = user['is_signed'] != true && user['is_signed'] != 1;
      Json reward = {};
      if (user['is_signed'] != true && user['is_signed'] != 1) {
        try {
          final result = await app.site.post('user/signin', {});
          reward = object(result['data']);
          // Re-read the authoritative state after POST, including a race with a background task.
          user = await account(uid);
        } catch (_) {
          user = await account(uid);
          if (user['is_signed'] != true && user['is_signed'] != 1) rethrow;
        }
      }
      if (!current(uid, generation)) return;
      if (user['is_signed'] != true && user['is_signed'] != 1) {
        throw ApiFailure(502, '暂未确认签到成功，请稍后重试');
      }
      app.user = user;
      if (wasUnsigned || latest['status'] != 'signed') {
        final all = object(app.local['checkinLatest']);
        all['$uid'] = {
          'time': DateTime.now().toUtc().toIso8601String(),
          'source': source,
          'status': 'signed',
          for (final key in ['continuous_signin', 'exp', 'point'])
            if (reward[key] is num) key: reward[key],
        };
        app.local['checkinLatest'] = all;
        await app.persist();
      }
      message = '今日已签到';
      _loginRequiredFor = '';
      _failures = 0;
      _scheduleWindows();
    } catch (_) {
      if (current(uid, generation)) message = '暂时未能完成签到，请检查网络与登录状态';
      rethrow;
    } finally {
      busy = false;
      changed();
      if (_automaticPending && !_disposed && !_stopping) {
        _automaticPending = false;
        unawaited(automatic(force: true));
      }
    }
  }

  Future<String> cloudToken({bool create = false}) async {
    final uid = app.uid, generation = app.generation;
    final key = 'checkin.cloud.$uid';
    final stored = await app.site.storage.read(key: key);
    if (stored != null) {
      try {
        final value = object(jsonDecode(stored));
        final token = text(value['token']);
        if (RegExp(r'^[a-f0-9]{64}$').hasMatch(token) &&
            number(value['user_id']) == uid &&
            (DateTime.tryParse(text(value['expires_at']))
                    ?.isAfter(DateTime.now()) ??
                false)) {
          return token;
        }
      } on FormatException {
        // A damaged or older local grant can be replaced after explicit consent.
      }
    }
    if (!create) return '';
    final grant = await app.service.request(
      '/checkin/v1/session',
      body: {'site_cookie': app.site.cookieHeader, 'expected_user_id': uid},
    );
    if (!current(uid, generation)) throw ApiFailure(409, '账号已切换');
    await app.site.storage.write(key: key, value: jsonEncode(grant));
    return text(grant['token']);
  }

  Future<void> refreshCloud() async {
    final uid = app.uid, generation = app.generation;
    final token = await cloudToken();
    if (token.isEmpty) return;
    try {
      final value = await app.service.request(
        '/checkin/v1/status',
        token: token,
      );
      if (current(uid, generation)) {
        cloud = value;
        changed();
      }
    } on ApiFailure catch (e) {
      if (e.status == 401) {
        await app.site.storage.delete(key: 'checkin.cloud.$uid');
        if (current(uid, generation)) {
          cloud = {};
          changed();
        }
      }
      rethrow;
    }
  }

  Future<void> setCloud(bool enabled) async {
    final uid = app.uid, generation = app.generation;
    var token = await cloudToken(create: enabled);
    if (token.isEmpty) return;
    if (!current(uid, generation)) throw ApiFailure(409, '账号已切换');
    Future<Json> send() => app.service.request(
      '/checkin/v1/${enabled ? 'enable' : 'disable'}',
      token: token,
      body: enabled
          ? {'site_cookie': app.site.cookieHeader, 'consent': true}
          : {},
    );
    Json result;
    try {
      try {
        result = await send();
      } on ApiFailure catch (e) {
        if (e.status != 401 || !enabled) rethrow;
        // Local expiry cannot detect a revoked server grant. Renew at most once,
        // only for the enable operation for which consent was just obtained.
        await app.site.storage.delete(key: 'checkin.cloud.$uid');
        if (!current(uid, generation)) throw ApiFailure(409, '账号已切换');
        token = await cloudToken(create: true);
        if (!current(uid, generation)) throw ApiFailure(409, '账号已切换');
        result = await send();
      }
    } catch (_) {
      // A response can be lost after the server commits. Read authoritative state
      // before reporting failure, without repeating the enable/disable request.
      if (current(uid, generation)) {
        try {
          await refreshCloud();
          if (current(uid, generation) && cloud['enabled'] == enabled) return;
        } catch (_) {}
      }
      rethrow;
    }
    if (current(uid, generation)) {
      cloud = result;
      changed();
    }
  }

  Future<void> stopForLogout() async {
    _stopping = true;
    _windowsTimer?.cancel();
    _windowsTimer = null;
    _automaticPending = false;
    if (isAndroid) {
      try {
        await platformChannel.invokeMethod('configureCheckinBackground', {
          'enabled': false,
          'uid': 0,
        });
      } catch (_) {}
    }
    // Revocation is attempted before erasing the local session. Offline grants are
    // kept only in the device vault so they can be revoked on a later login.
    try {
      await setCloud(false);
    } catch (_) {}
    cloud = {};
    background = {};
    message = '';
    _automaticCheck = DateTime(2000);
  }

  @override
  void dispose() {
    _disposed = true;
    _windowsTimer?.cancel();
    super.dispose();
  }
}
