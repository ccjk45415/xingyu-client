import 'dart:io';

class NetworkProxyConfig {
  final String mode, scope, host;
  final int port;
  const NetworkProxyConfig({
    this.mode = 'system',
    this.scope = 'all',
    this.host = '',
    this.port = 7890,
  });
  factory NetworkProxyConfig.parse(dynamic raw) {
    final value = raw is Map ? raw : const {};
    final mode = value['mode'] ?? 'system', scope = value['scope'] ?? 'all';
    final host = (value['host'] is String ? value['host'] as String : '')
        .trim();
    final port = int.tryParse('${value['port'] ?? 7890}') ?? 0;
    if (!['system', 'direct', 'manual'].contains(mode) ||
        !['all', 'updates'].contains(scope)) {
      throw const FormatException('代理选项无效');
    }
    if (mode == 'manual' &&
        (host.isEmpty ||
            host.length > 253 ||
            port < 1 ||
            port > 65535 ||
            !RegExp(r'^[A-Za-z0-9.\-:\[\]]+$').hasMatch(host) ||
            ((host.contains(':') || host.contains('[') || host.contains(']')) &&
                InternetAddress.tryParse(
                      host.replaceAll('[', '').replaceAll(']', ''),
                    )?.type !=
                    InternetAddressType.IPv6))) {
      throw const FormatException('请填写有效的代理主机和端口，不需要 http:// 或账号密码');
    }
    return NetworkProxyConfig(mode: mode, scope: scope, host: host, port: port);
  }
  Map<String, dynamic> toJson() => {
    'mode': mode,
    'scope': scope,
    'host': host,
    'port': port,
  };
  String get authority =>
      '${host.contains(':') && !host.startsWith('[') ? '[$host]' : host}:$port';
  bool applies(Uri uri) =>
      scope == 'all' ||
      [
        'api.shorebird.dev',
        'cdn.shorebird.cloud',
        'download.shorebird.dev',
        'storage.googleapis.com',
      ].contains(uri.host) ||
      uri.path.startsWith('/updates/') ||
      uri.path.startsWith('/releases/');
  String directive(Uri uri, String Function(Uri) system) => mode == 'direct'
      ? 'DIRECT'
      : mode == 'manual' && applies(uri)
      ? 'PROXY $authority'
      : system(uri);
}
