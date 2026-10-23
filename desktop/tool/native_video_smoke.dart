// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:xingyu_desktop/ui/inline_video.dart';

void main() {
  testWidgets('native decoder plays and seeks MP4/HLS in default muted state', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final root = Directory(Directory.current.resolveSymbolicLinksSync())
          .parent
          .path;
      final folder = Directory('$root/desktop/build/video-smoke');
      MediaKit.ensureInitialized(
        libmpv: '$root/desktop/build/windows/native-x64/libmpv/libmpv-2.dll',
      );
      NativePlayer.test =
          true; // null audio/video outputs; real native decoding
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serving = server.listen((request) async {
        final file = File('${folder.path}/${request.uri.pathSegments.last}');
        if (!await file.exists()) {
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }
        final bytes = await file.readAsBytes();
        var start = 0, end = bytes.length - 1;
        final range = RegExp(r'bytes=(\d+)-(\d*)')
            .firstMatch(request.headers.value('range') ?? '');
        if (range != null) {
          start = int.parse(range[1]!);
          end = range[2]!.isEmpty ? end : int.parse(range[2]!);
          request.response.statusCode = 206;
          request.response.headers.set(
            'Content-Range',
            'bytes $start-$end/${bytes.length}',
          );
        }
        request.response.headers.set('Accept-Ranges', 'bytes');
        request.response.headers.set(
          'Content-Type',
          file.path.endsWith('.mp4')
              ? 'video/mp4'
              : file.path.endsWith('.m3u8')
              ? 'application/vnd.apple.mpegurl'
              : 'video/mp2t',
        );
        request.response.contentLength = end - start + 1;
        request.response.add(bytes.sublist(start, end + 1));
        await request.response.close();
      });
      final observations = <Map<String, dynamic>>[];
      try {
        for (final name in ['synthetic.mp4', 'synthetic.m3u8']) {
          final player = Player(configuration: articleVideoConfiguration);
          try {
            await player
                .open(
                  Media('http://127.0.0.1:${server.port}/$name'),
                  play: false,
                )
                .timeout(const Duration(seconds: 15));
            await player.stream.duration
                .firstWhere((d) => d.inMilliseconds > 1000)
                .timeout(const Duration(seconds: 15));
            expect(player.state.volume, 0);
            await player.play();
            await player.stream.position
                .firstWhere((p) => p.inMilliseconds >= 400)
                .timeout(const Duration(seconds: 15));
            expect(player.state.volume, 0);
            expect(player.state.playing, true);
            await player.pause();
            await player.seek(const Duration(seconds: 2));
            await Future<void>.delayed(const Duration(milliseconds: 300));
            expect(player.state.playing, false);
            expect(player.state.volume, 0);
            expect(player.state.videoParams.w, greaterThan(0));
            observations.add({
              'format': name.split('.').last,
              'decoded_width': player.state.videoParams.w,
              'duration_ms': player.state.duration.inMilliseconds,
              'muted_volume': player.state.volume,
              'play_pause_seek': true,
            });
          } finally {
            await player.dispose();
          }
        }
      } finally {
        await serving.cancel();
        await server.close(force: true);
      }
      await File('$root/evidence/native-video-validation.json').writeAsString(
        jsonEncode({
          'decoder': 'libmpv',
          'synthetic_only': true,
          'browser_used': false,
          'native_decoding': observations,
          'physical_android_test': 'pending_user',
        }),
      );
    });
  });
}
