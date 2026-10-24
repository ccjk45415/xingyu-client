import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'native_storage.dart';

typedef Json = Map<String, dynamic>;
Json object(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Json> rows(dynamic v) =>
    v is List ? v.whereType<Map>().map(object).toList() : <Json>[];
String text(dynamic v, [String fallback = '']) =>
    v == null ? fallback : v.toString();
int number(dynamic v) => v is num ? v.toInt() : int.tryParse(text(v)) ?? 0;
String nonce() => List.generate(
  24,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
const siteOrigin = 'https://cangku.moe';
// Public ingress is configuration, not a secret; access is enforced by verified bearer tokens.
final serviceOrigin = String.fromCharCodes(
  [
    5,
    248,
    223,
    186,
    154,
    50,
    8,
    105,
    29,
    237,
    205,
    165,
    152,
    117,
    50,
    93,
    53,
    29,
    239,
    151,
    186,
    155,
    125,
    93,
    97,
    65,
    167,
    131,
    228,
    222,
    127,
    79,
    42,
    9,
    248,
    132,
    173,
    141,
    113,
  ].indexed.map((v) => v.$2 ^ ((0x6d + v.$1 * 31) & 255)),
);
const desktopVersion = '0.6.0-test';
const desktopBuild = 25;
bool safeExternal(String raw) {
  final u = Uri.tryParse(raw);
  return u != null &&
      ((['http', 'https'].contains(u.scheme) &&
              u.host.isNotEmpty &&
              u.userInfo.isEmpty) ||
          u.scheme == 'magnet');
}

int articleId(String raw) {
  final u = Uri.tryParse(raw);
  if (u == null ||
      u.scheme != 'https' ||
      u.host != 'cangku.moe' ||
      u.userInfo.isNotEmpty ||
      u.hasPort && u.port != 443) {
    return 0;
  }
  return int.tryParse(
        RegExp(r'^/archives/(\d+)/?$').firstMatch(u.path)?.group(1) ?? '',
      ) ??
      0;
}

class ApiFailure implements Exception {
  final int status;
  final String message;
  ApiFailure(this.status, this.message);
  @override
  String toString() => message;
}

class SocketConnector {
  HttpClient? _connecting;
  void cancel() {
    final current = _connecting;
    _connecting = null;
    current?.close(force: true);
  }

  Future<WebSocket> connect(String url, {Map<String, dynamic>? headers}) async {
    cancel();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    _connecting = client;
    try {
      return await WebSocket.connect(
        url,
        headers: headers,
        customClient: client,
        maxPayloadLength: 256 * 1024,
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          client.close(force: true);
          throw TimeoutException('聊天服务连接超时，请重试');
        },
      );
    } finally {
      if (identical(_connecting, client)) _connecting = null;
      client.close(force: true);
    }
  }
}

Future<Uint8List> bounded(Stream<List<int>> stream, int max) async {
  final out = BytesBuilder(copy: false);
  await for (final chunk in stream.timeout(const Duration(seconds: 35))) {
    if (out.length + chunk.length > max) throw ApiFailure(413, '返回内容过大');
    out.add(chunk);
  }
  return out.takeBytes();
}

class SiteApi {
  final HttpClient _client;
  final SecureVault storage;
  final Map<String, Cookie> _cookies = {};
  bool remember = false;
  int generation = 0;
  SiteApi({HttpClient? client, SecureVault? secureStorage})
    : _client = client ?? HttpClient(),
      storage = secureStorage ?? const SecureVault() {
    _client.connectionTimeout = const Duration(seconds: 18);
  }
  String get cookieHeader => _cookies.values
      .where((c) => c.expires == null || c.expires!.isAfter(DateTime.now()))
      .map((c) => '${c.name}=${c.value}')
      .join('; ');
  Future<bool> restore() async {
    final raw = await storage.read(key: 'website.cookies');
    if (raw == null) return false;
    try {
      for (final v in rows(jsonDecode(raw))) {
        final c = Cookie.fromSetCookieValue(text(v['cookie']));
        if (c.domain != null &&
            !['cangku.moe', '.cangku.moe'].contains(c.domain)) {
          continue;
        }
        _cookies[c.name] = c;
      }
      remember = true;
      return cookieHeader.isNotEmpty;
    } catch (_) {
      await clear();
      return false;
    }
  }

  Future<void> clear() async {
    generation++;
    _cookies.clear();
    remember = false;
    await storage.delete(key: 'website.cookies');
  }

  Future<void> persist() async {
    if (remember) {
      await storage.write(
        key: 'website.cookies',
        value: jsonEncode(
          _cookies.values.map((c) => {'cookie': c.toString()}).toList(),
        ),
      );
    } else {
      await storage.delete(key: 'website.cookies');
    }
  }

  Future<Json> login(String account, String password, bool keep) async {
    await clear();
    await request('/login', api: false);
    final result = await post('auth/login', {
      'login': account,
      'password': password,
      'remember': keep,
      'include': 'roles,permissions,meta',
    });
    final u = object(result['data']);
    if (number(u['id']) <= 0) throw ApiFailure(400, '官网登录返回无效的用户资料');
    if (u['should_verify_otp'] == true) {
      throw ApiFailure(428, '请先在官网完成二次验证后再登录');
    }
    remember = keep;
    await persist();
    return u;
  }

  Future<Json> get(String path, [Map<String, dynamic>? params]) =>
      request(path, params: params);
  Future<Json> post(String path, Json body) => request(path, body: body);
  Future<Json> request(
    String path, {
    Map<String, dynamic>? params,
    Json? body,
    bool api = true,
  }) async {
    final current = generation;
    final sessionCookie = cookieHeader;
    final csrfValue = _cookies['XSRF-TOKEN']?.value;
    final uri = Uri.parse('$siteOrigin${api ? '/api/v1/' : ''}$path')
        .replace(queryParameters: params?.map((k, v) => MapEntry(k, text(v))));
    if (uri.host != 'cangku.moe' || uri.scheme != 'https') {
      throw ApiFailure(400, '站点地址无效');
    }
    final request = await _client
        .openUrl(body == null ? 'GET' : 'POST', uri)
        .timeout(const Duration(seconds: 20));
    if (current != generation) {
      request.abort();
      throw ApiFailure(409, '账号已切换，请重试');
    }
    request.followRedirects = false;
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'Mozilla/5.0 XingyuDesktop/$desktopVersion',
    );
    request.headers.set('Accept', 'application/json');
    request.headers.set('Origin', siteOrigin);
    request.headers.set('Referer', '$siteOrigin/');
    request.headers.set('X-Requested-With', 'XMLHttpRequest');
    if (sessionCookie.isNotEmpty) request.headers.set('Cookie', sessionCookie);
    if (csrfValue != null) {
      request.headers.set('X-XSRF-TOKEN', Uri.decodeComponent(csrfValue));
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 35));
    final bytes = await bounded(response, 8 * 1024 * 1024);
    if (current != generation) throw ApiFailure(409, '账号已切换，请重试');
    for (final c in response.cookies) {
      if (c.domain != null &&
          !['cangku.moe', '.cangku.moe'].contains(c.domain)) {
        continue;
      }
      if (c.maxAge == 0 ||
          c.expires != null && c.expires!.isBefore(DateTime.now())) {
        _cookies.remove(c.name);
      } else {
        _cookies[c.name] = c;
      }
    }
    if ([301, 302, 303, 307, 308, 401, 419].contains(response.statusCode)) {
      throw ApiFailure(response.statusCode, '登录已过期，请重新登录');
    }
    if (!api) return {};
    Json result;
    try {
      result = object(jsonDecode(utf8.decode(bytes)));
    } catch (_) {
      throw ApiFailure(response.statusCode, '网站返回格式异常，请稍后重试');
    }
    if (response.statusCode >= 400 || number(result['code']) != 0) {
      throw ApiFailure(response.statusCode, text(result['message'], '请求失败'));
    }
    await persist();
    return result;
  }

  Future<Json> upload(
    String path,
    String field,
    Uint8List data, [
    Json fields = const {},
  ]) async {
    final current = generation, boundary = 'Xingyu${nonce()}';
    final sessionCookie = cookieHeader;
    final csrfValue = _cookies['XSRF-TOKEN']?.value;
    final request = await _client.postUrl(
      Uri.parse('$siteOrigin/api/v1/$path'),
    );
    if (current != generation) {
      request.abort();
      throw ApiFailure(409, '账号已切换，请重试');
    }
    request.followRedirects = false;
    request.headers.set(
      'Content-Type',
      'multipart/form-data; boundary=$boundary',
    );
    request.headers.set('Cookie', sessionCookie);
    request.headers.set(
      'User-Agent',
      'Mozilla/5.0 XingyuDesktop/$desktopVersion',
    );
    request.headers.set('Origin', siteOrigin);
    request.headers.set('Referer', '$siteOrigin/');
    request.headers.set('X-Requested-With', 'XMLHttpRequest');
    if (csrfValue != null) {
      request.headers.set('X-XSRF-TOKEN', Uri.decodeComponent(csrfValue));
    }
    for (final e in fields.entries) {
      if (!RegExp(r'^[a-z_]+$').hasMatch(e.key)) throw ApiFailure(400, '字段无效');
      request.add(
        utf8.encode(
          '--$boundary\r\nContent-Disposition: form-data; name="${e.key}"\r\n\r\n${e.value}\r\n',
        ),
      );
    }
    final (extension, mime) = uploadImageType(data);
    request.add(
      utf8.encode(
        '--$boundary\r\nContent-Disposition: form-data; name="$field"; filename="upload.$extension"\r\nContent-Type: $mime\r\n\r\n',
      ),
    );
    request.add(data);
    request.add(utf8.encode('\r\n--$boundary--\r\n'));
    final response = await request.close();
    final bytes = await bounded(response, 2 * 1024 * 1024);
    if (current != generation) throw ApiFailure(409, '账号已切换');
    final result = object(jsonDecode(utf8.decode(bytes)));
    if (response.statusCode >= 400 || number(result['code']) != 0) {
      throw ApiFailure(response.statusCode, text(result['message'], '上传失败'));
    }
    return result;
  }

  void close() => _client.close(force: true);
}

class ServiceApi {
  final String origin;
  ServiceApi({String? origin}) : origin = origin ?? serviceOrigin;
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  Future<Json> request(
    String path, {
    String? token,
    Json? body,
    String? method,
  }) async {
    final response = await send(
      path,
      token: token,
      body: body == null
          ? null
          : Uint8List.fromList(utf8.encode(jsonEncode(body))),
      method: method,
      type: 'application/json',
    );
    return object(jsonDecode(utf8.decode(response)));
  }

  Future<Uint8List> send(
    String path, {
    String? token,
    Uint8List? body,
    String? method,
    String? type,
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse('$origin$path');
    if (uri.origin != origin) throw ApiFailure(400, '服务地址无效');
    final r = await client
        .openUrl(method ?? (body == null ? 'GET' : 'POST'), uri)
        .timeout(const Duration(seconds: 20));
    r.followRedirects = false;
    r.headers.set('Cache-Control', 'no-cache');
    r.headers.set('User-Agent', 'XingyuDesktop/$desktopVersion');
    if (token != null) r.headers.set('Authorization', 'Bearer $token');
    headers.forEach(r.headers.set);
    if (body != null) {
      r.headers.set('Content-Type', type ?? 'image/jpeg');
      r.contentLength = body.length;
      r.add(body);
    }
    final response = await r.close().timeout(const Duration(seconds: 25));
    final bytes = await bounded(response, 2 * 1024 * 1024);
    if (response.statusCode >= 300) {
      String reason = '服务暂时不可用';
      try {
        reason = text(object(jsonDecode(utf8.decode(bytes)))['error'], reason);
      } catch (_) {}
      throw ApiFailure(response.statusCode, reason);
    }
    return bytes;
  }

  void close() => client.close(force: true);
}

/// Preserve the original image format for website comment uploads (including GIF).
(String, String) uploadImageType(Uint8List bytes) {
  bool prefix(List<int> signature, [int offset = 0]) =>
      bytes.length >= signature.length + offset &&
      List.generate(
        signature.length,
        (i) => bytes[offset + i] == signature[i],
      ).every((x) => x);
  if (prefix([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    return ('png', 'image/png');
  }
  if (prefix([0x47, 0x49, 0x46, 0x38])) return ('gif', 'image/gif');
  if (prefix([0x52, 0x49, 0x46, 0x46]) && prefix([0x57, 0x45, 0x42, 0x50], 8)) {
    return ('webp', 'image/webp');
  }
  return ('jpg', 'image/jpeg');
}
