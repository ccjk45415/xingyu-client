import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../ui/shared.dart';
import 'api.dart';
import 'platform.dart';

String get updatePlatform => isAndroid
    ? 'android'
    : isMacOS
    ? 'macos-arm64'
    : 'windows-x64';
String get updateManifestPath => isAndroid
    ? '/updates/android.json'
    : isMacOS
    ? '/updates/macos.json'
    : '/updates/windows.json';

void validateClientRelease(Json manifest, String platform) {
  final extension = switch (platform) {
    'windows-x64' => 'zip',
    'macos-arm64' => 'pkg',
    'android' => 'apk',
    _ => throw ApiFailure(400, '不支持的更新平台'),
  };
  final url = Uri.tryParse(text(manifest['url']));
  if ((platform == 'android'
          ? manifest['package'] != 'moe.cangku.reader'
          : manifest['platform'] != platform) ||
      number(manifest['versionCode']) < 1 ||
      !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(text(manifest['versionName'])) ||
      number(manifest['size']) < 1 ||
      number(manifest['size']) > 160 * 1024 * 1024 ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(text(manifest['sha256'])) ||
      url == null ||
      url.origin != serviceOrigin ||
      !RegExp('^/releases/[A-Za-z0-9._-]+\\.$extension\$').hasMatch(url.path) ||
      url.hasQuery ||
      url.hasFragment ||
      url.userInfo.isNotEmpty) {
    throw ApiFailure(400, '更新文件信息不完整或来源无效');
  }
}

void validateWindowsRelease(Json manifest) =>
    validateClientRelease(manifest, 'windows-x64');
Future<void> checkWindowsUpdate(BuildContext context) =>
    checkClientUpdate(context);

Future<void> verifyReleaseFile(File file, Json manifest) async {
  if (await file.length() != number(manifest['size']) ||
      (await sha256.bind(file.openRead()).first).toString() !=
          manifest['sha256']) {
    throw ApiFailure(400, '更新包校验失败，未安装更新，请重新下载');
  }
}

Future<File> downloadVerifiedRelease(
  Json manifest,
  Directory directory,
  void Function(double) progress,
) async {
  validateClientRelease(manifest, updatePlatform);
  await directory.create(recursive: true);
  final uri = Uri.parse(text(manifest['url']));
  final file = File('${directory.path}/${uri.pathSegments.last}');
  final part = File('${file.path}.part');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  IOSink? sink;
  try {
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    final response = await request.close().timeout(const Duration(seconds: 35));
    if (response.statusCode != 200) {
      throw ApiFailure(response.statusCode, '下载暂时不可用，请稍后重试');
    }
    final expected = number(manifest['size']);
    if (response.contentLength >= 0 && response.contentLength != expected) {
      throw ApiFailure(400, '更新文件大小不匹配');
    }
    sink = part.openWrite();
    var received = 0;
    await for (final chunk in response.timeout(const Duration(seconds: 35))) {
      received += chunk.length;
      if (received > expected) throw ApiFailure(400, '更新文件大小不匹配');
      sink.add(chunk);
      progress(received / expected);
    }
    await sink.flush();
    await sink.close();
    sink = null;
    await verifyReleaseFile(part, manifest);
    return await part.rename(file.path);
  } finally {
    client.close(force: true);
    await sink?.close();
    if (await part.exists()) await part.delete();
  }
}

Future<void> checkClientUpdate(
  BuildContext context, {
  Json? release,
  bool confirmed = false,
}) async {
  final app = stateOf(context), platform = updatePlatform;
  final manifest = release ?? await app.service.request(updateManifestPath);
  if (!context.mounted) return;
  if (manifest['available'] != true) {
    message(context, '当前没有可用的新版本');
    return;
  }
  validateClientRelease(manifest, platform);
  if (number(manifest['versionCode']) <= clientBuild) {
    message(context, '已经是最新版本 $clientVersion');
    return;
  }
  final instructions = platform == 'windows-x64'
      ? '下载并校验后自动替换程序、重新启动。请先保存正在编辑的投稿。'
      : '下载并校验后自动打开系统安装程序，请按系统提示确认安装。';
  if ((!confirmed &&
          !await confirm(
            context,
            '发现新版本 ${text(manifest['versionName'])}',
            '${text(manifest['notes'])}\n\n$instructions',
            action: '下载并更新',
          )) ||
      !context.mounted) {
    return;
  }
  final temporary = await getTemporaryDirectory();
  if (!context.mounted) return;
  final directory = Directory('${temporary.path}/xingyu-update-${nonce()}');
  final file = await showDialog<File>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DownloadUpdate(manifest, directory),
  );
  if (file == null || !context.mounted) return;
  if (platform == 'android') {
    await platformChannel.invokeMethod<void>('installUpdate', {
      'path': file.path,
      'sha256': manifest['sha256'],
      'versionCode': number(manifest['versionCode']),
    });
  } else if (platform == 'macos-arm64') {
    final result = await Process.run('/usr/bin/open', [file.path]);
    if (result.exitCode != 0) throw ApiFailure(500, '无法打开系统安装程序，请稍后重试');
    if (context.mounted) message(context, '更新安装器已打开，安装完成后重新打开星屿。');
  } else {
    await prepareWindowsUpdate(file, manifest, directory);
    if (!context.mounted) return;
    await Process.start('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      '${directory.path}/update.ps1',
      '-Mode',
      'Apply',
      '-Job',
      '${directory.path}/job.json',
    ], mode: ProcessStartMode.detached);
    // Only the verified managed bundle is replaced, after the helper sees this
    // process exit. Account data and drafts live outside the program directory.
    exit(0);
  }
}

Future<void> prepareWindowsUpdate(
  File archive,
  Json manifest,
  Directory directory,
) async {
  final script = File('${directory.path}/update.ps1');
  await script.writeAsString(
    await rootBundle.loadString('assets/windows-update.ps1'),
    flush: true,
  );
  await File('${directory.path}/job.json').writeAsString(
    jsonEncode({
      'archive': archive.path,
      'install': File(Platform.resolvedExecutable).parent.path,
      'parentPid': pid,
      'sha256': manifest['sha256'],
      'versionCode': number(manifest['versionCode']),
      'versionName': manifest['versionName'],
    }),
    flush: true,
  );
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-WindowStyle',
    'Hidden',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    script.path,
    '-Mode',
    'Prepare',
    '-Job',
    '${directory.path}/job.json',
  ]);
  if (result.exitCode != 0) {
    throw ApiFailure(500, '无法准备更新。请确认程序目录可写且未被其他星屿进程占用，当前版本未被替换。');
  }
}

class _DownloadUpdate extends StatefulWidget {
  final Json manifest;
  final Directory directory;
  const _DownloadUpdate(this.manifest, this.directory);
  @override
  State<_DownloadUpdate> createState() => _DownloadUpdateState();
}

class _DownloadUpdateState extends State<_DownloadUpdate> {
  double progress = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => start());
  }

  Future<void> start() async {
    try {
      final file = await downloadVerifiedRelease(
        widget.manifest,
        widget.directory,
        (value) {
          if (mounted) setState(() => progress = value);
        },
      );
      if (mounted) Navigator.of(context).pop(file);
    } catch (e) {
      if (mounted) {
        setState(() => error = e is ApiFailure ? e.message : '下载中断，请检查网络后重试');
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: error != null,
    child: AlertDialog(
      title: const Text('正在准备更新'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.system_update_alt_rounded,
              size: 42,
              color: violet,
            ),
            const SizedBox(height: 20),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 14),
            Text(error ?? '${(progress * 100).floor()}% · 下载完成后校验安装包'),
          ],
        ),
      ),
      actions: error == null
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
    ),
  );
}

/// A release is offered once per installation, regardless of the active account.
/// Invalid/offline responses never consume the reminder, and cancellation never installs.
Future<void> offerStartupUpdate(BuildContext context) async {
  final app = stateOf(context);
  final manifest = await app.service.request(updateManifestPath);
  if (!context.mounted || manifest['available'] != true) return;
  validateClientRelease(manifest, updatePlatform);
  final code = number(manifest['versionCode']);
  if (code <= clientBuild) return;
  final key = '$updatePlatform:$code';
  final offered =
      (app.local['updateOffers'] is List
              ? app.local['updateOffers'] as List
              : [])
          .whereType<String>()
          .toSet();
  if (offered.contains(key)) return;
  offered.add(key);
  app.local['updateOffers'] = offered
      .toList()
      .reversed
      .take(20)
      .toList()
      .reversed
      .toList();
  await app.persist();
  if (!context.mounted) return;
  final accept = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(
        Icons.system_update_alt_rounded,
        color: violet,
        size: 34,
      ),
      title: Text('发现新版本 ${text(manifest['versionName'])}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(child: Text(text(manifest['notes']))),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('暂时不更新'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('立即更新'),
        ),
      ],
    ),
  );
  if (accept == true && context.mounted) {
    await checkClientUpdate(context, release: manifest, confirmed: true);
  }
}
