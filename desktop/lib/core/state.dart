import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'browse_cache.dart';
import 'following_feed.dart';
import 'client_config.dart';
import 'checkin.dart';
import 'patch_updates.dart';
import 'in_app_notices.dart';

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
  int generation = 0, socialRevision = 0;
  final Map<int, Json> authorCache = {};
  late final ClientConfigStore clientConfig = ClientConfigStore(this);
  late final CheckinController checkin = CheckinController(this);
  late final PatchUpdates patches = PatchUpdates();
  late final InAppNotices notices = InAppNotices(this);
  late final FollowingFeedStore followingFeed = FollowingFeedStore(
    get: get,
    social: (path) => social(path),
    active: () => verified && uid > 0,
  );
  VoidCallback? onLogout;
  bool _syncing = false;
  DateTime _checkedProfile = DateTime(2000);
  AppState({
    SiteApi? siteApi,
    ServiceApi? serviceApi,
    SocketConnector Function()? socketFactory,
  }) : site = siteApi ?? SiteApi(),
       service = serviceApi ?? ServiceApi(),
       socketFactory = socketFactory ?? SocketConnector.new {
    clientConfig.addListener(notifyListeners);
    checkin.addListener(notifyListeners);
    patches.addListener(notifyListeners);
  }
  int get uid => number(user?['id']);
  String get token => text(identity?['token']);
  bool get verified =>
      token.isNotEmpty &&
      DateTime.tryParse(text(identity?['expires_at']))
              ?.isAfter(DateTime.now()) ==
          true;
  List<Json> get history => rows(object(local['history'])['$uid']);
  Json get drafts => object(object(local['drafts'])['$uid']);
  Future<void> initialize() async {
    try {
      directory = await getApplicationSupportDirectory();
      await directory!.create(recursive: true);
      BrowseCache.shared.directory = Directory(
        '${directory!.path}/browse-cache',
      );
      final file = File('${directory!.path}/library.json');
      if (await file.exists() && await file.length() < 8 * 1024 * 1024) {
        try {
          local = object(jsonDecode(await file.readAsString()));
        } catch (_) {}
      }
      BrowseCache.shared.enabled = local['cacheEnabled'] != false;
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
    if (user == null) await notices.stopSystem();
    starting = false;
    notifyListeners();
    unawaited(clientConfig.initialize());
    unawaited(patches.check());
    unawaited(checkin.automatic());
    if (user != null) unawaited(loadCategories());
  }

  Future<void> login(String account, String password, bool keep) async {
    final result = await site.login(account.trim(), password, keep);
    await notices.stopSystem();
    notices.clear();
    followingFeed.clear();
    user = result;
    generation++;
    await loadIdentity();
    startupError = null;
    notifyListeners();
    unawaited(loadCategories());
    unawaited(checkin.automatic(force: true));
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
    final owner = uid, current = generation;
    try {
      final result = rows(
        (await get('category/list', {'all': '1', 'type': 'post'}))['data'],
      );
      if (uid != owner || generation != current) return;
      categories = result;
      notifyListeners();
    } catch (_) {}
  }

  final Map<String, Future<Json>> _browsingFlights = {};

  DateTime bypassCacheUntil = DateTime(2000);
  void refreshBrowsing() {
    bypassCacheUntil = DateTime.now().add(const Duration(seconds: 3));
  }

  Future<Json> get(String path, [Map<String, dynamic>? params]) {
    if (!cacheableRead(path, params)) return _read(path, params);
    final key =
        '$generation:${browsingKey(uid, path, params)}:${Zone.current[browsingRevalidate] == true || DateTime.now().isBefore(bypassCacheUntil)}';
    final previous = _browsingFlights[key];
    if (previous != null) return previous;
    late final Future<Json> flight;
    flight = _read(path, params).whenComplete(() {
      if (identical(_browsingFlights[key], flight)) {
        _browsingFlights.remove(key);
      }
    });
    _browsingFlights[key] = flight;
    return flight;
  }

  Future<Json> _read(String path, Map<String, dynamic>? params) async {
    final account = uid,
        current = generation,
        cacheEpoch = BrowseCache.shared.epoch;
    final cacheable = account > 0 && cacheableRead(path, params);
    final key = browsingKey(account, path, params);
    final force =
        Zone.current[browsingRevalidate] == true ||
        DateTime.now().isBefore(bypassCacheUntil);
    if (cacheable && !force) {
      final cached = await BrowseCache.shared.json(
        key,
        maxAge: path == 'category/list'
            ? const Duration(days: 1)
            : const Duration(minutes: 5),
      );
      if (cached != null && account == uid && current == generation) {
        return {...cached, '_xingyu_cache': true};
      }
    }
    try {
      final value = await site.get(path, params);
      if (uid != account || generation != current) {
        throw ApiFailure(409, '账号已切换');
      }
      if (cacheable) {
        unawaited(
          BrowseCache.shared.putJson(key, value, generation: cacheEpoch),
        );
      }
      return value;
    } on ApiFailure catch (e) {
      if ([301, 302, 303, 401, 419].contains(e.status)) await logout();
      if (cacheable &&
          e.status >= 500 &&
          uid == account &&
          generation == current) {
        final old = await BrowseCache.shared.json(key);
        if (old != null && uid == account && generation == current) {
          return {...old, '_xingyu_cache': true, '_xingyu_offline': true};
        }
      }
      rethrow;
    } on IOException {
      if (cacheable && uid == account && generation == current) {
        final old = await BrowseCache.shared.json(key);
        if (old != null && uid == account && generation == current) {
          return {...old, '_xingyu_cache': true, '_xingyu_offline': true};
        }
      }
      rethrow;
    } on TimeoutException {
      if (cacheable && uid == account && generation == current) {
        final old = await BrowseCache.shared.json(key);
        if (old != null && uid == account && generation == current) {
          return {...old, '_xingyu_cache': true, '_xingyu_offline': true};
        }
      }
      rethrow;
    }
  }

  Future<Json> post(String path, Json body) async {
    try {
      final value = await site.post(path, body);
      refreshBrowsing();
      return value;
    } on ApiFailure catch (e) {
      if ([301, 302, 303, 401, 419].contains(e.status)) await logout();
      rethrow;
    }
  }

  Future<Json> social(String path, {Json? body}) async {
    final owner = uid, current = generation, secret = token;
    if (!verified) throw ApiFailure(401, '请先认证仓库账号');
    try {
      final value = await service.request(path, token: secret, body: body);
      if (uid != owner || generation != current) throw ApiFailure(409, '账号已切换');
      return value;
    } on ApiFailure catch (e) {
      if (e.status == 401 &&
          uid == owner &&
          generation == current &&
          token == secret) {
        followingFeed.clear();
        identity = null;
        await site.storage.delete(key: 'chat.$owner');
        notifyListeners();
      }
      rethrow;
    }
  }

  void socialChanged() {
    followingFeed.clear();
    socialRevision++;
    notifyListeners();
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
    await notices.stopSystem();
    notices.pause();
    notices.clear();
    await checkin.stopForLogout();
    followingFeed.clear();
    onLogout?.call();
    final owner = uid, secret = token;
    generation++;
    user = null;
    identity = null;
    categories = [];
    authorCache.clear();
    socialRevision++;
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
    followingFeed.clear();
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
  Json get submissionHabits =>
      object(object(local['submissionHabits'])['$uid']);
  Future<void> setSubmissionHabits(Json value) async {
    final all = object(local['submissionHabits']);
    all['$uid'] = value;
    local['submissionHabits'] = all;
    await persist();
    notifyListeners();
  }

  Future<void> setCacheEnabled(bool enabled) async {
    BrowseCache.shared.enabled = enabled;
    local['cacheEnabled'] = enabled;
    await persist();
    notifyListeners();
  }

  Future<void> setDark(bool value) async {
    dark = value;
    notifyListeners();
    await persist();
  }

  bool get categoryTopNavigation =>
      object(local['categoryLayout'])['$uid'] == 'tabs';
  Set<int>? get homeCategories {
    final pref = object(object(local['homeCategories'])['$uid']);
    if (pref['enabled'] != true) return null;
    return (pref['ids'] as List? ?? [])
        .map(number)
        .where((id) => id > 0)
        .toSet();
  }

  String get homeFilterKey => homeCategories == null
      ? 'all'
      : ((homeCategories!.toList()..sort()).join(','));
  Future<void> setHomeCategories(Set<int>? value) async {
    final accounts = object(local['homeCategories']);
    accounts['$uid'] = {'enabled': value != null, 'ids': value?.toList() ?? []};
    local['homeCategories'] = accounts;
    notifyListeners();
    await persist();
  }

  Future<void> setCategoryLayout(bool tabs) async {
    final accounts = object(local['categoryLayout']);
    accounts['$uid'] = tabs ? 'tabs' : 'cards';
    local['categoryLayout'] = accounts;
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
    notices.dispose();
    patches.removeListener(notifyListeners);
    patches.dispose();
    checkin.removeListener(notifyListeners);
    checkin.dispose();
    clientConfig.removeListener(notifyListeners);
    clientConfig.dispose();
    site.close();
    service.close();
    super.dispose();
  }
}
