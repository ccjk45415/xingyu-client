import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'native_storage.dart';

/// Keeps bounded, private diagnostics. Never stores error messages or network data.
class DiagnosticEntry {
  final String time, source, type, frames;
  const DiagnosticEntry(this.time, this.source, this.type, this.frames);
  static String safeType(Object error) =>
      RegExp(r'^[A-Za-z_$][A-Za-z0-9_$<>]{0,79}$')
          .hasMatch('${error.runtimeType}')
      ? '${error.runtimeType}'
      : 'Error';
  static String locations(StackTrace stack) {
    final package = RegExp(
      r'package:([a-zA-Z0-9_]+(?:/[a-zA-Z0-9_.-]+)*\.dart):(\d+)(?::(\d+))?',
    );
    final native = RegExp(
      r'^\s*#(\d+)\s+abs\s+([0-9a-f]+)\s+virt\s+([0-9a-f]+)',
      caseSensitive: false,
    );
    final result = <String>[];
    for (final line in '$stack'.split('\n').take(512)) {
      final match = package.firstMatch(line), address = native.firstMatch(line);
      if (match != null) {
        result.add('  at ${match.group(0)}');
      } else if (address != null) {
        result.add('  #${address[1]} abs ${address[2]} virt ${address[3]}');
      }
      if (result.length >= 32) break;
    }
    return result.isEmpty ? '  无可用的安全调用位置' : result.join('\n');
  }

  Map<String, String> toJson() => {
    'time': time,
    'source': source,
    'type': type,
    'frames': frames,
  };
}

class DiagnosticStore extends ChangeNotifier {
  static const storageKey = 'xingyu.diagnostics.v1';
  final SecureVault vault;
  final List<DiagnosticEntry> _entries = [];
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  bool storageAvailable = true;
  DiagnosticStore({this.vault = const SecureVault()});
  List<DiagnosticEntry> get entries => List.unmodifiable(_entries);
  Future<void> initialize() => _loading ??= _load();
  Future<void> _load() async {
    try {
      final raw = await vault.read(key: storageKey);
      if (raw != null && raw.length < 192000) {
        final value = jsonDecode(raw);
        if (value is List) {
          for (final item in value.take(10)) {
            if (item is! Map) continue;
            final time = DateTime.tryParse('${item['time']}');
            final source = '${item['source']}', type = '${item['type']}';
            if (time == null ||
                !RegExp(r'^[a-z-]{1,32}$').hasMatch(source) ||
                !RegExp(r'^[A-Za-z_$][A-Za-z0-9_$<>]{0,79}$').hasMatch(type)) {
              continue;
            }
            _entries.add(
              DiagnosticEntry(
                time.toUtc().toIso8601String(),
                source,
                type,
                DiagnosticEntry.locations(
                  StackTrace.fromString('${item['frames']}'),
                ),
              ),
            );
          }
        }
      }
    } catch (_) {
      storageAvailable = false;
    }
    notifyListeners();
  }

  Future<void> record(Object error, StackTrace stack, String source) async {
    await initialize();
    final safeSource = RegExp(r'^[a-z-]{1,32}$').hasMatch(source)
        ? source
        : 'unknown';
    _entries.insert(
      0,
      DiagnosticEntry(
        DateTime.now().toUtc().toIso8601String(),
        safeSource,
        DiagnosticEntry.safeType(error),
        DiagnosticEntry.locations(stack),
      ),
    );
    if (_entries.length > 10) _entries.removeRange(10, _entries.length);
    notifyListeners();
    final payload = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await _enqueue(() => vault.write(key: storageKey, value: payload));
  }

  Future<void> _enqueue(Future<void> Function() work) {
    return _writes = _writes.then((_) async {
      try {
        await work();
        storageAvailable = true;
      } catch (_) {
        storageAvailable = false;
      }
      notifyListeners();
    });
  }

  Future<void> clear() async {
    await initialize();
    _entries.clear();
    notifyListeners();
    await _enqueue(() => vault.delete(key: storageKey));
  }

  String report() => [
    '星屿本机诊断',
    'Version: $desktopVersion ($desktopBuild)',
    'Engine: Flutter Desktop / Dart ${Platform.version.split('\n').first}',
    'OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    '',
    '仅保存在本机，不自动上传。最近最多保留10条异常；不记录密码、会话、API Key、请求正文或异常消息。',
    if (!storageAvailable) '本机安全存储暂不可用，当前记录可能仅保留到退出。',
    if (_entries.isEmpty) '\n暂无异常记录。',
    for (final e in _entries)
      '\nTime (UTC): ${e.time}\nStep: ${e.source}\n${e.type}\n${e.frames}',
  ].join('\n');
}

final appDiagnostics = DiagnosticStore();
