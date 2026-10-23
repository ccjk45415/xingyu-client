import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/updates.dart';

void main() {
  test('platform updater selects separate Windows and macOS feeds', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(updateManifestPath, '/updates/windows.json');
    expect(updatePlatform, 'windows-x64');
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(updateManifestPath, '/updates/macos.json');
    expect(updatePlatform, 'macos-arm64');
    debugDefaultTargetPlatformOverride = null;
  });
  test(
    'all platforms reject external, redirected-looking and mismatched packages',
    () {
      for (final entry in {
        'windows-x64': 'zip',
        'macos-arm64': 'pkg',
        'android': 'apk',
      }.entries) {
        final good = <String, dynamic>{
          'platform': entry.key,
          'package': 'moe.cangku.reader',
          'versionName': '1.2.3',
          'versionCode': 100,
          'size': 123,
          'sha256': 'a' * 64,
          'url': '$serviceOrigin/releases/client.${entry.value}',
        };
        validateClientRelease(good, entry.key);
        for (final patch in [
          {'url': 'https://evil.test/releases/client.${entry.value}'},
          {'url': '$serviceOrigin/releases/client.${entry.value}?redirect=bad'},
          {'url': '$serviceOrigin/releases/client.${entry.value}#bad'},
          {'url': '$serviceOrigin/releases/sub/client.${entry.value}'},
          {'url': '$serviceOrigin/releases/client.exe'},
          {'sha256': 'invalid'},
          {'size': 161 * 1024 * 1024},
          {'size': 0},
          {'versionCode': 0},
          {'versionName': '../bad'},
          if (entry.key == 'android')
            {'package': 'another.app'}
          else
            {'platform': 'another-platform'},
        ]) {
          expect(
            () => validateClientRelease({...good, ...patch}, entry.key),
            throwsA(isA<ApiFailure>()),
            reason: '$entry $patch',
          );
        }
      }
    },
  );
  test('download verification rejects truncated or altered files', () async {
    final directory = await Directory.systemTemp.createTemp(
      'xingyu-update-hash-',
    );
    final file = File('${directory.path}/package.bin');
    try {
      final bytes = [1, 2, 3, 4];
      final metadata = {
        'size': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      };
      await file.writeAsBytes(bytes);
      await verifyReleaseFile(file, metadata);
      await file.writeAsBytes([1, 2, 3]);
      await expectLater(
        verifyReleaseFile(file, metadata),
        throwsA(isA<ApiFailure>()),
      );
      await file.writeAsBytes([1, 2, 3, 5]);
      await expectLater(
        verifyReleaseFile(file, metadata),
        throwsA(isA<ApiFailure>()),
      );
    } finally {
      await file.delete();
      await directory.delete();
    }
  });
}
