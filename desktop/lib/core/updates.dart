import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../ui/shared.dart';
import 'api.dart';

void validateWindowsRelease(Json manifest) {
  final url = Uri.tryParse(text(manifest['url'])),
      hash = text(manifest['sha256']);
  if (manifest['platform'] != 'windows-x64' ||
      number(manifest['versionCode']) < 1 ||
      number(manifest['size']) < 1 ||
      number(manifest['size']) > 160 * 1024 * 1024 ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
      url == null ||
      url.origin != serviceOrigin ||
      !url.path.startsWith('/releases/') ||
      !url.path.endsWith('.zip') ||
      url.hasQuery ||
      url.hasFragment ||
      url.userInfo.isNotEmpty) {
    throw ApiFailure(400, 'Windows更新文件信息不完整或来源无效');
  }
}

Future<void> checkWindowsUpdate(BuildContext context) async {
  final app = stateOf(context);
  final manifest = await app.service.request('/updates/windows.json');
  if (!context.mounted) return;
  if (manifest['available'] != true) {
    message(context, '当前没有新的Windows版本');
    return;
  }
  validateWindowsRelease(manifest);
  if (number(manifest['versionCode']) <= desktopBuild) {
    message(context, '已经是最新版本 $desktopVersion');
    return;
  }
  if (await confirm(
        context,
        '发现 Windows ${text(manifest['versionName'])}',
        '${text(manifest['notes'])}\n\n下载后校验文件大小与SHA-256。退出星屿后解压新版，保留完整目录再运行。',
        action: '选择位置并下载',
      ) &&
      context.mounted) {
    await downloadWindowsRelease(context, manifest);
  }
}

Future<void> downloadWindowsRelease(BuildContext context, Json manifest) async {
  validateWindowsRelease(manifest);
  final uri = Uri.parse(text(manifest['url']));
  final destination = await getSaveLocation(
    suggestedName: uri.pathSegments.last,
    acceptedTypeGroups: [
      const XTypeGroup(label: 'ZIP压缩包', extensions: ['zip']),
    ],
  );
  if (destination == null || !context.mounted) return;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  final part = File('${destination.path}.xingyu.part');
  try {
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    final response = await request.close();
    if (response.statusCode != 200) {
      throw ApiFailure(response.statusCode, '下载失败，请稍后重试');
    }
    final bytes = await bounded(response, number(manifest['size']) + 1);
    if (bytes.length != number(manifest['size']) ||
        sha256.convert(bytes).toString() != manifest['sha256']) {
      throw ApiFailure(400, '更新包校验失败，未保存下载文件');
    }
    await part.writeAsBytes(bytes, flush: true);
    await part.rename(destination.path);
    if (context.mounted) message(context, '新版已校验并保存。退出星屿后解压，运行完整目录内的程序。');
  } finally {
    client.close(force: true);
    if (await part.exists()) await part.delete();
  }
}
