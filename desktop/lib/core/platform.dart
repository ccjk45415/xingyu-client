import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;
import 'package:flutter/foundation.dart';

const androidTestVersion = '0.11.0';
const androidTestBuild = 33;
const androidTestChannel = bool.fromEnvironment(
  'XINGYU_ANDROID_TEST',
  defaultValue: false,
);
const platformChannel = MethodChannel('moe.cangku.xingyu/platform');
bool get isAndroid => Platform.isAndroid;
bool get isMacOS => defaultTargetPlatform == TargetPlatform.macOS;
const macosTestVersion = '0.1.1';
const macosTestBuild = 2;
String get clientVersion => isAndroid
    ? androidTestVersion
    : isMacOS
    ? macosTestVersion
    : '0.5.0';
int get clientBuild => isAndroid
    ? androidTestBuild
    : isMacOS
    ? macosTestBuild
    : 24;
String? get uiFont => isAndroid || isMacOS ? null : 'Microsoft YaHei UI';
String get monoFont => isAndroid
    ? 'monospace'
    : isMacOS
    ? 'Menlo'
    : 'Consolas';
String get primaryModifierLabel => isMacOS ? '⌘' : 'Ctrl';
String get backShortcutLabel => isMacOS ? '⌘[' : 'Alt+←';
String get secureStorageLabel => isAndroid
    ? 'Android Keystore'
    : isMacOS
    ? 'macOS 钥匙串'
    : 'Windows 安全存储';
SingleActivator primaryShortcut(LogicalKeyboardKey key, {bool shift = false}) =>
    SingleActivator(key, control: !isMacOS, meta: isMacOS, shift: shift);

String proxyDirective(dynamic host, dynamic port) {
  if (host is! String ||
      port is! num ||
      !port.isFinite ||
      port.toInt() != port ||
      port < 1 ||
      port > 65535 ||
      host.isEmpty ||
      !RegExp(r'^[A-Za-z0-9.\-:\[\]]+$').hasMatch(host)) {
    return 'DIRECT';
  }
  final address = host.contains(':') && !host.startsWith('[')
      ? '[$host]'
      : host;
  return 'PROXY $address:${port.toInt()}';
}

/// Dart's sockets follow VPN routing. Honor the native explicit HTTP proxy too.
/// Refresh when resuming so users can switch their proxy without restarting.
class AndroidProxyOverrides extends HttpOverrides {
  String proxy = 'DIRECT';
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (_) => proxy;
    return client;
  }
}

final _proxy = AndroidProxyOverrides();
Future<void> initializePlatform() async {
  if (!isAndroid && !isMacOS) return;
  HttpOverrides.global = _proxy;
  await refreshSystemProxy();
}

Future<void> refreshSystemProxy() async {
  if (!isAndroid && !isMacOS) return;
  final value = await platformChannel.invokeMapMethod<String, dynamic>('proxy');
  _proxy.proxy = proxyDirective(value?['host'], value?['port']);
}

/// Native media backend uses the same explicit proxy as Dart requests.
String get nativeMediaProxy => _proxy.proxy.startsWith('PROXY ')
    ? 'http://${_proxy.proxy.substring(6)}'
    : '';
