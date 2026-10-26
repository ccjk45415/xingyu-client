import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;
import 'package:flutter/foundation.dart';

const androidTestVersion = String.fromEnvironment(
  'XINGYU_ANDROID_VERSION',
  defaultValue: '0.13.1',
);
const androidTestBuild = int.fromEnvironment(
  'XINGYU_ANDROID_BUILD',
  defaultValue: 37,
);
const androidTestChannel = bool.fromEnvironment(
  'XINGYU_ANDROID_TEST',
  defaultValue: false,
);
const platformChannel = MethodChannel('moe.cangku.xingyu/platform');
bool get isAndroid => Platform.isAndroid;
bool get isMacOS => defaultTargetPlatform == TargetPlatform.macOS;
bool get isWindows => defaultTargetPlatform == TargetPlatform.windows;
const macosTestVersion = '0.3.1';
const macosTestBuild = 6;
String get clientVersion => isAndroid
    ? androidTestVersion
    : isMacOS
    ? macosTestVersion
    : '0.7.1';
int get clientBuild => isAndroid
    ? androidTestBuild
    : isMacOS
    ? macosTestBuild
    : 28;
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
  String? windowsServer;
  String windowsBypass = '';
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (uri) => windowsServer == null
        ? proxy
        : windowsProxyDirective(uri, windowsServer!, windowsBypass);
    return client;
  }
}

final _proxy = AndroidProxyOverrides();
Future<void> initializePlatform() async {
  if (!isAndroid && !isMacOS && !Platform.isWindows) return;
  HttpOverrides.global = _proxy;
  await refreshSystemProxy();
}

Future<void> refreshSystemProxy() async {
  if (!isAndroid && !isMacOS && !Platform.isWindows) return;
  final value = await platformChannel.invokeMapMethod<String, dynamic>('proxy');
  if (Platform.isWindows) {
    _proxy.windowsServer = value?['server'] as String? ?? '';
    _proxy.windowsBypass = value?['bypass'] as String? ?? '';
    _proxy.proxy = windowsProxyDirective(
      Uri.parse('https://cangku.moe'),
      _proxy.windowsServer!,
      _proxy.windowsBypass,
    );
    return;
  }
  _proxy.proxy = proxyDirective(value?['host'], value?['port']);
}

/// Windows manual system proxy, including per-protocol servers and bypass rules.
/// PAC-only configurations continue to use the device's routing (e.g. TUN).
String windowsProxyDirective(Uri uri, String server, String bypass) {
  final host = uri.host.toLowerCase();
  for (final item in bypass.toLowerCase().split(';')) {
    final rule = item.trim();
    if (rule.isEmpty) continue;
    if (rule == '<local>') {
      if (!host.contains('.') && !host.contains(':')) return 'DIRECT';
    } else if (RegExp(
      '^${RegExp.escape(rule).replaceAll(r'\*', '.*').replaceAll(r'\?', '.')}'
      r'$',
    ).hasMatch(host)) {
      return 'DIRECT';
    }
  }
  String? selected, common;
  for (final item in server.split(';')) {
    final pair = item.trim().split('=');
    if (pair.length == 1) {
      common = pair[0];
    } else if (pair.length == 2 && pair[0].trim().toLowerCase() == uri.scheme) {
      selected = pair[1].trim();
    }
  }
  final address = selected ?? common;
  if (address == null ||
      address.isEmpty ||
      address.contains('@') ||
      address.contains('/') ||
      RegExp(r'\s').hasMatch(address)) {
    return 'DIRECT';
  }
  final endpoint = Uri.tryParse('http://$address');
  if (endpoint == null || !endpoint.hasPort || endpoint.userInfo.isNotEmpty) {
    return 'DIRECT';
  }
  return proxyDirective(endpoint.host, endpoint.port);
}

/// Native media backend uses the same explicit proxy as Dart requests.
String get nativeMediaProxy => _proxy.proxy.startsWith('PROXY ')
    ? 'http://${_proxy.proxy.substring(6)}'
    : '';

/// Respect per-host proxy bypass rules for third-party video CDNs as well.
String nativeMediaProxyFor(String url) {
  final uri = Uri.tryParse(url);
  final directive = _proxy.windowsServer == null || uri == null
      ? _proxy.proxy
      : windowsProxyDirective(uri, _proxy.windowsServer!, _proxy.windowsBypass);
  return directive.startsWith('PROXY ')
      ? 'http://${directive.substring(6)}'
      : '';
}
