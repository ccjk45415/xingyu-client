import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'api.dart';

class AppState extends ChangeNotifier {
  final SiteApi site;
  final ServiceApi service;
  final SocketConnector Function() socketFactory;
  Json? user, identity;
  Json local = {};
  List<Json> categories = [];
  bool starting = true, dark = false;
  double fontSize = 17;
  String? startupError;
  Directory? directory;
  int generation = 0;
  VoidCallback? onLogout;
  bool _syncing = false;
  DateTime _checkedProfile = DateTime(2000);
  AppState({
    SiteApi? siteApi,
    ServiceApi? serviceApi,
    SocketConnector Function()? socketFactory,
  }) : site = siteApi ?? SiteApi(),
       service = serviceApi ?? ServiceApi(),
       socketFactory = socketFactory ?? SocketConnector.new;
  int get uid => number(user?['id']);
  String get token => text(identity?['token']);
  bool get verified =>
      token.isNotEmpty &&
      DateTime.tryParse(
            text(identity?['expires_at']),
          )?.isAfter(DateTime.now()) ==
          true;
  List<Json> get history => rows(object(local['history'])['$uid']);
  Json get drafts => object(object(local['drafts'])['$uid']);
  Future<void> initialize() async {
    try {
      directory = await getApplicationSupportDirectory();
      await directory!.create(recursive: true);
      final file = File('${directory!.path}/library.json');
      if (await file.exists() && await file.length() < 8 * 1024 * 1024) {
        try {
          local = object(jsonDecode(await file.readAsString()));
        } catch (_) {}
      }
      dark = local['dark'] == true;
      fontSize = (local['fontSize'] as num?)?.toDouble().clamp(13, 26) ?? 17;
      if (await site.restore()) {
        try {
          user = object(
            (await site.get('auth/me', {
              'include': 'roles,permissions,meta',
            }))['data'],
          );
          await loadIdentity();
        } on ApiFailure catch (e) {
          if ([301, 302, 303, 401, 419].contains(e.status)) {
            await site.clear();
            user = null;
          } else {
            startupError = e.message;
          }
        }
      }
    } catch (e) {
      startupError = '本机资料暂时无法读取：$e';
    }
    starting = false;
    notifyListeners();
    if (user != null) unawaited(loadCategories());
  }

  Future<void> login(String account, String password, bool keep) async {
    final result = await site.login(account.trim(), password, keep);
    user = result;
    generation++;
    await loadIdentity();
    startupError = null;
    notifyListeners();
    unawaited(loadCategories());
  }

  Future<void> loadIdentity() async {
    identity = null;
    final raw = await site.storage.read(key: 'chat.$uid');
    if (raw != null) {
      try {
        final v = object(jsonDecode(raw));
        if (number(object(v['user'])['id']) == uid) identity = v;
      } catch (_) {}
    }
    if (!verified) identity = null;
  }

  Future<void> loadCategories() async {
    try {
      categories = rows(
        (await get('category/list', {'all': '1', 'type': 'post'}))['data'],
      );
      notifyListeners();
    } catch (_) {}
  }

  Future<Json> get(String path, [Map<String, dynamic>? params]) async {
    try {
      return await site.get(path, params);
    } on ApiFailure catch (e) {
      if ([301, 302, 303, 401, 419].contains(e.status)) await logout();
      rethrow;
    }
  }

  Future<Json> post(String path, Json body) async {
    try {
      return await site.post(path, body);
    } on ApiFailure catch (e) {
      if ([301, 302, 303, 401, 419].contains(e.status)) await logout();
      rethrow;
    }
  }

  Future<void> refreshUser() async {
    final owner = uid,
        value = object(
          (await get('auth/me', {'include': 'roles,permissions,meta'}))['data'],
        );
    if (owner != uid || number(value['id']) != owner) {
      throw ApiFailure(409, '账号已切换');
    }
    user = value;
    notifyListeners();
    await syncProfile(force: true);
  }

  Future<void> enableIdentity() async {
    final owner = uid, current = generation;
    if (owner <= 0 || site.cookieHeader.isEmpty) {
      throw ApiFailure(401, '请先登录仓库账号');
    }
    final session = await service.request(
      '/dm/v1/session',
      body: {'site_cookie': site.cookieHeader, 'expected_user_id': owner},
    );
    if (generation != current ||
        owner != uid ||
        number(object(session['user'])['id']) != owner) {
      throw ApiFailure(409, '账号已切换，认证未保存');
    }
    identity = session;
    await site.storage.write(key: 'chat.$owner', value: jsonEncode(session));
    notifyListeners();
  }

  Future<void> syncProfile({bool force = false}) async {
    if (!verified ||
        _syncing ||
        !force && DateTime.now().difference(_checkedProfile).inSeconds < 60) {
      return;
    }
    _syncing = true;
    final owner = uid, current = generation, secret = token;
    try {
      final latest = object(
        (await site.get('auth/me', {
          'include': 'roles,permissions,meta',
        }))['data'],
      );
      if (generation != current || uid != owner || token != secret) return;
      if (number(latest['id']) != owner) throw ApiFailure(403, '官网身份不匹配');
      final old = object(identity?['user']);
      if (text(old['nickname']) != text(latest['nickname']) ||
          text(old['avatar']) != text(latest['avatar'])) {
        final result = await service.request(
          '/dm/v1/profile/sync',
          token: secret,
          body: {'site_cookie': site.cookieHeader},
        );
        if (generation != current || uid != owner || token != secret) return;
        identity!['user'] = result['user'];
        await site.storage.write(
          key: 'chat.$owner',
          value: jsonEncode(identity),
        );
        await service.request('/v1/me', token: secret);
      }
      user = latest;
      _checkedProfile = DateTime.now();
      notifyListeners();
    } finally {
      _syncing = false;
    }
  }

  Future<void> logout() async {
    onLogout?.call();
    final owner = uid, secret = token;
    generation++;
    user = null;
    identity = null;
    categories = [];
    notifyListeners();
    await site.clear();
    if (owner > 0) await site.storage.delete(key: 'chat.$owner');
    if (secret.isNotEmpty) {
      try {
        await service.request('/dm/v1/logout', token: secret, body: {});
      } catch (_) {}
    }
  }

  void expireIdentity() {
    identity = null;
    notifyListeners();
  }

  Future<void> persist() async {
    if (directory == null) return;
    local['dark'] = dark;
    local['fontSize'] = fontSize;
    final file = File('${directory!.path}/library.json');
    // Serialize writes so rapid theme/draft updates cannot corrupt the local library.
    final contents = jsonEncode(local);
    _writes = _writes
        .catchError((_) {})
        .then((_) => file.writeAsString(contents, flush: true).then((_) {}));
    await _writes;
  }

  Future<void> _writes = Future.value();
  Future<void> setDark(bool value) async {
    dark = value;
    notifyListeners();
    await persist();
  }

  Future<void> setFont(double value) async {
    fontSize = value;
    notifyListeners();
    await persist();
  }

  Future<void> addHistory(Json post) async {
    final all = object(local['history']), list = rows(all['$uid']);
    list.removeWhere((v) => v['id'] == post['id']);
    list.insert(0, {
      for (final key in [
        'id',
        'title',
        'thumb',
        'user',
        'created_at',
        'view_count',
      ])
        key: post[key],
      'read_at': DateTime.now().toIso8601String(),
    });
    all['$uid'] = list.take(150).toList();
    local['history'] = all;
    await persist();
  }

  Future<void> saveDraft(String key, Json? value, {int? owner}) async {
    final account = owner ?? uid;
    final all = object(local['drafts']), mine = object(all['$account']);
    if (value == null) {
      mine.remove(key);
    } else {
      mine[key] = value;
    }
    all['$account'] = mine;
    local['drafts'] = all;
    await persist();
  }

  @override
  void dispose() {
    site.close();
    service.close();
    super.dispose();
  }
}
