import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xingyu_desktop/core/ai.dart';
import 'package:xingyu_desktop/core/api.dart';
import 'package:xingyu_desktop/core/video_source.dart';

import 'ai_test.dart' show Client, Request, Reply;

class VideoClient extends Client {
  final Map<String, Object> responses;
  final requests = <({Uri url, Request request})>[];
  VideoClient(this.responses) : super(Request(Reply('{}')));
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    final request = Request(Reply(jsonEncode(responses[url.path])));
    requests.add((url: url, request: request));
    return request;
  }
}

void main() {
  test('BV, AV, player links and page selection parse only official hosts', () {
    expect(
      BilibiliVideoRef.parse(
        Uri.parse('https://www.bilibili.com/video/BV1YQp16yE2M/?p=2'),
      )!.page,
      2,
    );
    expect(
      BilibiliVideoRef.parse(
        Uri.parse('https://player.bilibili.com/player.html?aid=123&page=3'),
      )!.identity,
      {'aid': '123'},
    );
    expect(
      BilibiliVideoRef.parse(
        Uri.parse('https://bilibili.com.evil.example/video/BV1YQp16yE2M/'),
      ),
      isNull,
    );
  });
  test('progressive resolver accepts safe complete video and backup, rejects split/private media', () {
    expect(
      bilibiliProgressiveUrls({
        'code': 0,
        'data': {
          'durl': [
            {
              'url': 'https://cdn.example.com/a.mp4',
              'backup_url': ['https://backup.example.com/a.mp4'],
            },
          ],
        },
      }),
      hasLength(2),
    );
    expect(
      () => bilibiliProgressiveUrls({
        'code': 0,
        'data': {
          'durl': [
            {'url': 'https://a.example/1.mp4'},
            {'url': 'https://a.example/2.mp4'},
          ],
        },
      }),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      () => bilibiliProgressiveUrls({'code': -10403}),
      throwsA(isA<ApiFailure>()),
    );
  });
  test('Bilibili API resolves selected CID and muxed stream without website cookies or script execution', () async {
    final client = VideoClient({
      '/x/web-interface/view': {
        'code': 0,
        'data': {
          'cid': 123,
          'pages': [
            {'cid': 123},
            {'cid': 456},
          ],
        },
      },
      '/x/player/playurl': {
        'code': 0,
        'data': {
          'durl': [
            {'url': 'https://cdn.example.com/movie.mp4', 'backup_url': null},
          ],
        },
      },
    });
    final io = AiTransport(
      http: client,
      lookup: (_) async => [InternetAddress('8.8.8.8')],
    );
    final video = await io.resolveVideo(
      'https://www.bilibili.com/video/BV1YQp16yE2M/?p=2',
      sourceUrl: 'https://cangku.moe/archives/229761',
    );
    expect(video.url, 'https://cdn.example.com/movie.mp4');
    expect(video.headers['Referer'], 'https://www.bilibili.com/');
    expect(client.requests.last.url.queryParameters['cid'], '456');
    expect(client.requests.last.url.queryParameters['fnval'], '0');
    for (final request in client.requests) {
      expect(request.url.host, 'api.bilibili.com');
      expect(request.request.headers.values.containsKey('Cookie'), isFalse);
      expect(
        request.request.headers.values.containsKey('Authorization'),
        isFalse,
      );
    }
    io.close();
  });
  test('invalid page and private media never yield playable URLs', () async {
    final client = VideoClient({
      '/x/web-interface/view': {
        'code': 0,
        'data': {
          'pages': [
            {'cid': 123},
          ],
        },
      },
      '/x/player/playurl': {
        'code': 0,
        'data': {
          'durl': [
            {'url': 'https://127.0.0.1/a.mp4'},
          ],
        },
      },
    });
    final io = AiTransport(
      http: client,
      lookup: (_) async => [InternetAddress('8.8.8.8')],
    );
    await expectLater(
      io.resolveVideo('https://www.bilibili.com/video/BV1YQp16yE2M/?p=2'),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      io.resolveVideo('https://www.bilibili.com/video/BV1YQp16yE2M/'),
      throwsA(isA<ApiFailure>()),
    );
    io.close();
  });
}
