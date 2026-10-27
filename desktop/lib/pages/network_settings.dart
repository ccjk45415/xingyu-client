import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/platform.dart';
import '../core/proxy_config.dart';
import '../core/native_proxy_environment.dart';
import '../ui/shared.dart';

class NetworkSettingsPage extends StatefulWidget {
  const NetworkSettingsPage({super.key});
  @override
  State<NetworkSettingsPage> createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends State<NetworkSettingsPage> {
  final host = TextEditingController(), port = TextEditingController();
  String mode = 'system', scope = 'all';
  bool loaded = false, busy = false;
  List<({String name, String result, bool ok})> results = [];
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!loaded) {
      loaded = true;
      final c = networkProxyConfig;
      mode = c.mode;
      scope = c.scope;
      host.text = c.host;
      port.text = '${c.port}';
    }
  }

  @override
  void dispose() {
    host.dispose();
    port.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final app = stateOf(context);
    late final NetworkProxyConfig config;
    try {
      config = NetworkProxyConfig.parse({
        'mode': mode,
        'scope': scope,
        'host': host.text,
        'port': port.text,
      });
    } on FormatException catch (e) {
      throw ApiFailure(400, e.message);
    }
    configureNetworkProxy(config.toJson());
    app.local['networkProxy'] = config.toJson();
    await app.persist();
    await syncNativeNetworkProxy();
    if (mounted) setState(() => results = []);
  }

  Future<void> probe() async {
    await save();
    if (!mounted) return;
    setState(() => busy = true);
    final endpoints = [
      ('仓库网站', Uri.parse('$siteOrigin/')),
      ('星屿服务', Uri.parse('$serviceOrigin/health')),
      ('补丁域名 HTTPS', Uri.parse('https://api.shorebird.dev/')),
    ];
    final values = await Future.wait(
      endpoints.map((entry) async {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 8);
        final timer = Stopwatch()..start();
        try {
          final req = await client
              .getUrl(entry.$2)
              .timeout(const Duration(seconds: 8));
          req.followRedirects = false;
          final response = await req.close().timeout(
            const Duration(seconds: 8),
          );
          await response.first
              .timeout(const Duration(seconds: 8))
              .catchError((_) => <int>[]);
          final ok =
              response.statusCode >= 200 &&
              (response.statusCode < 400 ||
                  entry.$2.host == 'api.shorebird.dev' &&
                      response.statusCode == 404);
          return (
            name: entry.$1,
            result: ok
                ? 'HTTPS 已连通 · ${timer.elapsedMilliseconds} ms'
                : 'HTTP ${response.statusCode} · 请检查代理规则',
            ok: ok,
          );
        } catch (_) {
          return (name: entry.$1, result: '连接失败 · 请检查地址、端口与局域网权限', ok: false);
        } finally {
          client.close(force: true);
        }
      }),
    );
    if (mounted) {
      setState(() {
        busy = false;
        results = values;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PageBody(
    width: 820,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Heading('网络与代理', '为网站访问、更新和补丁选择合适的连接方式。'),
        Surface(
          color: violet.withValues(alpha: .06),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(Icons.wifi_tethering_rounded),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '连接你的 Clash',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '手机填写运行 Clash 的电脑局域网 IP，电脑本机可填 127.0.0.1。Clash 需开启“允许局域网”，填写 HTTP 或 Mixed 端口。',
                      style: TextStyle(fontSize: 12, height: 1.7),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('连接方式', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.route_rounded),
                  labelText: '代理模式',
                ),
                items: const [
                  DropdownMenuItem(value: 'system', child: Text('跟随系统')),
                  DropdownMenuItem(value: 'direct', child: Text('直接连接')),
                  DropdownMenuItem(value: 'manual', child: Text('手动 HTTP 代理')),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() => mode = value!),
              ),
              if (mode == 'manual') ...[
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, box) {
                    final fields = [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: host,
                          decoration: const InputDecoration(
                            labelText: '代理主机',
                            hintText: '例如 192.168.1.100',
                            prefixIcon: Icon(Icons.computer_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: port,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '端口',
                            hintText: '7890',
                          ),
                        ),
                      ),
                    ];
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: fields,
                    );
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: scope,
                  decoration: const InputDecoration(
                    labelText: '代理范围',
                    prefixIcon: Icon(Icons.filter_alt_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('全部应用连接')),
                    DropdownMenuItem(
                      value: 'updates',
                      child: Text('仅安装包更新与热补丁'),
                    ),
                  ],
                  onChanged: busy
                      ? null
                      : (value) => setState(() => scope = value!),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                '设置仅影响星屿。应用内新连接与补丁引擎使用此配置，不修改系统代理或证书。仅代理更新时，其他连接继续跟随系统设置。',
                style: TextStyle(fontSize: 12, height: 1.7),
              ),
              if (isAndroid && clientBuild < 39)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    '当前安装包的系统后台任务仍使用系统代理；应用内连接及热补丁可使用此设置。新版安装包同时支持后台任务代理。',
                    style: TextStyle(fontSize: 12, height: 1.6),
                  ),
                ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: busy ? null : () => action(context, save),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('保存设置'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => action(context, probe),
                    icon: const Icon(Icons.network_check_rounded, size: 18),
                    label: Text(busy ? '正在检查' : '保存并测试连接'),
                  ),
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : () => action(context, () async {
                            final app = stateOf(context);
                            await save();
                            await app.patches.check(force: true);
                            if (mounted) setState(() {});
                          }),
                    icon: const Icon(Icons.system_update_alt_rounded, size: 18),
                    label: const Text('检查补丁'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (results.isNotEmpty) ...[
          const SizedBox(height: 16),
          Surface(
            child: Column(
              children: [
                for (final row in results)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: IconBadge(
                      row.ok
                          ? Icons.check_circle_outline_rounded
                          : Icons.error_outline_rounded,
                    ),
                    title: Text(row.name),
                    subtitle: Text(
                      row.result,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          stateOf(context).patches.message,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        if (!NativeProxyEnvironment.supported)
          const Text(
            '当前运行环境未能配置原生补丁代理，请检查诊断信息。',
            style: TextStyle(fontSize: 12, color: Colors.deepOrange),
          ),
      ],
    ),
  );
}
