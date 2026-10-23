import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Disposable browsing data only. Drafts, identities and settings live elsewhere.
class BrowseCache {
  static final shared = BrowseCache();
  Directory? directory;
  bool enabled = true;
  int epoch = 0;
  final int maxBytes;
  final int maxEntries;
  Future<void> _tail = Future.value();
  final Map<String, Future<Uint8List>> _images = {};
  final Map<String, ({Map<String, dynamic> value, DateTime at, int bytes})>
  _jsonMemory = {};
  String? _memoryDirectory;
  final Map<String, Uint8List> _imageMemory = {};
  HttpClient? _imageClient;
  int _writesSinceTrim = 0;
  DateTime _lastTrim = DateTime(2000);

  Map<String, dynamic>? peekJson(
    String key, {
    Duration maxAge = const Duration(days: 30),
  }) {
    if (_memoryDirectory != directory?.path) {
      _jsonMemory.clear();
      _memoryDirectory = directory?.path;
    }
    if (!enabled || directory == null) return null;
    final entry = _jsonMemory[key];
    if (entry == null || DateTime.now().difference(entry.at) > maxAge) {
      return null;
    }
    return entry.value;
  }

  void _remember(
    String key,
    Map<String, dynamic> value,
    DateTime at,
    int bytes,
  ) {
    peekJson(key);
    if (!enabled || directory == null || bytes > 2 * 1024 * 1024) return;
    _jsonMemory.remove(key);
    _jsonMemory[key] = (value: value, at: at, bytes: bytes);
    while (_jsonMemory.length > 48 ||
        _jsonMemory.values.fold<int>(0, (n, e) => n + e.bytes) >
            8 * 1024 * 1024) {
      _jsonMemory.remove(_jsonMemory.keys.first);
    }
  }

  BrowseCache({
    this.directory,
    this.maxBytes = 192 * 1024 * 1024,
    this.maxEntries = 1800,
  });

  Future<T> _serial<T>(Future<T> Function() work) {
    final next = _tail.catchError((_) {}).then((_) => work());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  String _name(String key) => sha256.convert(utf8.encode(key)).toString();
  Future<Uint8List?> read(
    String key, {
    Duration maxAge = const Duration(days: 30),
  }) async {
    if (!enabled || directory == null) return null;
    final generation = epoch;
    // Atomic cache writes let reads proceed without waiting for image writes.
    try {
      final file = File('${directory!.path}/${_name(key)}.bin');
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file ||
          stat.size > 12 * 1024 * 1024 ||
          DateTime.now().difference(stat.modified) > maxAge) {
        return null;
      }
      final bytes = await file.readAsBytes();
      return generation == epoch && enabled ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(
    String key,
    List<int> bytes, {
    int? generation,
    bool trim = true,
  }) async {
    final captured = generation ?? epoch;
    if (!enabled || directory == null || bytes.length > 12 * 1024 * 1024) {
      return;
    }
    await _serial(() async {
      if (!enabled || captured != epoch) return;
      try {
        await directory!.create(recursive: true);
        final file = File('${directory!.path}/${_name(key)}.bin');
        final temporary = File('${file.path}.pending');
        await temporary.writeAsBytes(bytes);
        await temporary.rename(file.path);
        _writesSinceTrim++;
        if (trim ||
            _writesSinceTrim >= 16 ||
            DateTime.now().difference(_lastTrim).inSeconds >= 30) {
          await _trim();
          _lastTrim = DateTime.now();
          _writesSinceTrim = 0;
        }
      } catch (_) {
        /* Cache failures must never break browsing. */
      }
    });
  }

  Future<List<File>> _files() async {
    if (directory == null || !await directory!.exists()) return [];
    return directory!
        .list(followLinks: false)
        .where(
          (f) =>
              f is File && RegExp(r'[/\\][a-f0-9]{64}\.bin$').hasMatch(f.path),
        )
        .cast<File>()
        .toList();
  }

  Future<void> _trim() async {
    final entries = <({File file, FileStat stat})>[];
    for (final file in await _files()) {
      entries.add((file: file, stat: await file.stat()));
    }
    entries.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    var bytes = entries.fold<int>(0, (n, e) => n + e.stat.size),
        count = entries.length;
    for (final e in entries) {
      if (bytes <= maxBytes &&
          count <= maxEntries &&
          DateTime.now().difference(e.stat.modified).inDays <= 30) {
        break;
      }
      await e.file.delete();
      bytes -= e.stat.size;
      count--;
    }
  }

  Future<({int bytes, int entries})> size() => _serial(() async {
    var bytes = 0, entries = 0;
    for (final f in await _files()) {
      bytes += await f.length();
      entries++;
    }
    return (bytes: bytes, entries: entries);
  });
  Future<void> clear() async {
    epoch++;
    _images.clear();
    _jsonMemory.clear();
    _imageMemory.clear();
    _imageClient?.close(force: true);
    _imageClient = null;
    await _serial(() async {
      for (final f in await _files()) {
        await f.delete();
      }
    });
  }

  Future<Map<String, dynamic>?> json(
    String key, {
    Duration maxAge = const Duration(days: 30),
  }) async {
    final memory = peekJson(key, maxAge: maxAge);
    if (memory != null) return memory;
    final captured = epoch;
    final bytes = await read(key, maxAge: maxAge);
    if (bytes == null) return null;
    try {
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map || captured != epoch || !enabled) return null;
      final result = Map<String, dynamic>.from(value);
      // Preserve disk age so an old cache entry is never treated as fresh.
      final at = (await File(
        '${directory!.path}/${_name(key)}.bin',
      ).stat()).modified;
      if (captured != epoch || !enabled) return null;
      _remember(key, result, at, bytes.length);
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<void> putJson(
    String key,
    Map<String, dynamic> value, {
    int? generation,
  }) {
    final bytes = utf8.encode(jsonEncode(value));
    if ((generation ?? epoch) == epoch) {
      _remember(key, value, DateTime.now(), bytes.length);
    }
    return write(key, bytes, generation: generation, trim: false);
  }

  Future<Uint8List> image(String url, {Map<String, String>? headers}) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return Future.error(const FormatException('图片地址无效'));
    }
    // Private messaging media must not enter the public browsing cache.
    final cacheable = !uri.path.startsWith('/media/');
    final key = 'image:$url';
    if (enabled && cacheable && _imageMemory.containsKey(key)) {
      return Future.value(_imageMemory[key]);
    }
    return _images.putIfAbsent(key, () async {
      final generation = epoch;
      try {
        final cached = cacheable ? await read(key) : null;
        if (cached != null && cached.isNotEmpty) return cached;
        final client = _imageClient ??= (HttpClient()
          ..connectionTimeout = const Duration(seconds: 18)
          ..idleTimeout = const Duration(seconds: 45)
          ..maxConnectionsPerHost = 6);
        {
          final req = await client
              .getUrl(uri)
              .timeout(const Duration(seconds: 20));
          headers?.forEach(req.headers.set);
          final response = await req.close().timeout(
            const Duration(seconds: 25),
          );
          if (response.statusCode != 200) throw HttpException('图片暂时无法加载');
          final data = BytesBuilder(copy: false);
          await for (final chunk in response.timeout(
            const Duration(seconds: 25),
          )) {
            if (data.length + chunk.length > 12 * 1024 * 1024) {
              throw const FormatException('图片过大');
            }
            data.add(chunk);
          }
          final bytes = data.takeBytes();
          if (cacheable && enabled && generation == epoch) {
            if (bytes.length <= 2 * 1024 * 1024) {
              _imageMemory[key] = bytes;
              while (_imageMemory.values.fold<int>(0, (n, e) => n + e.length) >
                  8 * 1024 * 1024) {
                _imageMemory.remove(_imageMemory.keys.first);
              }
            }
            unawaited(write(key, bytes, generation: generation, trim: false));
          }
          return bytes;
        }
      } finally {
        _images.remove(key);
      }
    });
  }
}

String browsingKey(int uid, String path, Map<String, dynamic>? params) {
  final keys = params?.keys.toList() ?? <String>[];
  keys.sort();
  return 'site:$uid:$path:${jsonEncode({for (final k in keys) k: '${params![k]}'})}';
}

bool cacheableRead(String path, Map<String, dynamic>? params) =>
    const {
      'category/list',
      'post/list',
      'post/search',
      'post/rank',
      'post/info',
      'user/info',
      'user/post',
      'user/list',
    }.contains(path) &&
    params?['status'] == null &&
    params?['exclude_view'] != 1 &&
    params?['exclude_view'] != '1';

/// AsyncPane refreshes public content while retaining its account-scoped snapshot.
const browsingRevalidate = #xingyuBrowsingRevalidate;
