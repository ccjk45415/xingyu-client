import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/media.dart';
import 'package:xingyu_desktop/core/reader.dart';
import 'package:xingyu_desktop/core/updates.dart';
import 'package:xingyu_desktop/pages/authoring.dart';

void main() {
  test(
    'scheduled website dates retain Shanghai time when editing existing posts',
    () {
      expect(
        siteTimestamp('2026-10-20T18:35:02.000000Z'),
        '2026-10-21 02:35:02',
      );
      expect(siteTimestamp('2026-10-21 02:35:02'), '2026-10-21 02:35:02');
      expect(siteTimestamp('2026-10-21T02:35:02+08:00'), '2026-10-21 02:35:02');
    },
  );
  test(
    'external links and internal article routes keep authentication boundaries',
    () {
      expect(articleId('https://cangku.moe/archives/123'), 123);
      for (final url in [
        'https://cangku.moe.evil.test/archives/123',
        'http://cangku.moe/archives/123',
        'https://user@cangku.moe/archives/123',
        'https://cangku.moe:444/archives/123',
      ]) {
        expect(articleId(url), 0, reason: url);
      }
      for (final url in [
        'file:///C:/Windows',
        'javascript:alert(1)',
        'data:text/html,secret',
        'https://user:pass@example.com',
      ]) {
        expect(safeExternal(url), false);
      }
      expect(safeExternal('magnet:?xt=urn:btih:test'), true);
    },
  );
  test(
    'download shortcodes preserve escaped links and reject executable schemes',
    () {
      final doc = ReaderDocument.parse(
        '<script>bad()</script><p>正文</p>[dlbox title="资源 &amp; 收藏" info="说明" link1="网盘|https://example.com/a?x=1&amp;y=2" link2="危险|javascript:bad()"][/dlbox]',
      );
      expect(doc.resources.single.title, '资源 & 收藏');
      expect(doc.resources.single.links, {
        '网盘': 'https://example.com/a?x=1&y=2',
      });
      expect(doc.content.contains('<script>'), false);
      expect(doc.content.contains('正文'), true);
    },
  );
  test('rank dates use Shanghai day, Sunday week and year boundary', () {
    expect(rankParameters('daily', DateTime.parse('2026-12-31T16:30:00Z')), {
      'year': 2027,
      'date_type': 'daily',
      'date_value': 1,
    });
    expect(
      rankParameters(
        'monthly',
        DateTime.parse('2026-10-31T16:30:00Z'),
      )['date_value'],
      11,
    );
    expect(
      rankParameters(
        'weekly',
        DateTime.parse('2027-01-02T00:00:00Z'),
      )['date_value'],
      1,
    );
    expect(
      rankParameters(
        'weekly',
        DateTime.parse('2027-01-03T00:00:00Z'),
      )['date_value'],
      2,
    );
  });
  test('Windows update metadata cannot substitute external files or APKs', () {
    final good = {
      'platform': 'windows-x64',
      'versionCode': 2,
      'size': 1024,
      'sha256': 'a' * 64,
      'url': '$serviceOrigin/releases/Xingyu-Windows-0.2.0.zip',
    };
    validateWindowsRelease(good);
    for (final patch in [
      {'url': 'https://evil.test/releases/update.zip'},
      {'url': '$serviceOrigin/releases/fake.apk'},
      {'platform': 'android'},
      {'size': 0},
      {'size': 200 * 1024 * 1024},
      {'sha256': 'bad'},
    ]) {
      expect(
        () => validateWindowsRelease({...good, ...patch}),
        throwsA(isA<ApiFailure>()),
      );
    }
  });
  test(
    'image recompression has bounded JPEG dimensions, no source metadata and white transparency',
    () {
      final source = img.Image(width: 1800, height: 1000, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(255, 0, 0, 0));
      source.textData = {'private-source-metadata': 'must-not-leave-client'};
      final encoded = compressImage(img.encodePng(source));
      final decoded = img.decodeJpg(encoded)!;
      expect(encoded.length, lessThanOrEqualTo(192 * 1024));
      expect(decoded.width, lessThanOrEqualTo(1280));
      expect(decoded.height, lessThanOrEqualTo(1280));
      expect(latin1.decode(encoded).contains('must-not-leave-client'), false);
      expect(decoded.getPixel(0, 0).r, greaterThan(240));
      expect(
        () => compressImage(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  test(
    'edit conflict fingerprint ignores response order but detects content, status and categories',
    () {
      final post = {
        'title': '作品',
        'content': '正文',
        'status': 'draft',
        'thumb': '',
        'created_at': '2026-10-21',
        'categories': [
          {'id': 2},
          {'id': 1},
        ],
        'tags': [
          {'name': 'b'},
          {'name': 'a'},
        ],
      };
      final original = postFingerprint(post);
      expect(
        postFingerprint({
          ...post,
          'categories': [
            {'id': 1},
            {'id': 2},
          ],
          'tags': [
            {'name': 'a'},
            {'name': 'b'},
          ],
        }),
        original,
      );
      expect(
        postFingerprint({...post, 'content': '网站上更新过的正文'}),
        isNot(original),
      );
      expect(postFingerprint({...post, 'status': 'publish'}), isNot(original));
    },
  );
}
