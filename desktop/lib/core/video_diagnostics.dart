import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../ui/inline_video.dart';

Future<void> runVideoPreviewCheck(String fixture) async {
  final key = GlobalKey();
  final scroll = ScrollController();
  try {
    if (!await File(fixture).exists()) {
      throw StateError('Synthetic clip missing');
    }
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scroll,
            child: Column(
              children: [
                SizedBox(
                  width: 640,
                  child: InlineArticleVideo(
                    key: key,
                    url: 'https://example.com/synthetic.mp4',
                    mediaResolver: (_) async {
                      await Future<void>.delayed(
                        const Duration(milliseconds: 120),
                      );
                      return File(fixture).absolute.path;
                    },
                    playerFactory: () => Player(
                      configuration: const PlayerConfiguration(muted: true),
                    ),
                  ),
                ),
                const SizedBox(height: 1600),
              ],
            ),
          ),
        ),
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    final dynamic state = key.currentState;
    Future<void> ready() async {
      for (var i = 0; i < 200; i++) {
        if (state.firstFrame == true) return;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      throw StateError('Preview not ready');
    }

    await ready();
    final player = state.player as Player;
    if (player.state.playing ||
        player.state.volume != 0 ||
        player.state.videoParams.w != 320) {
      throw StateError('Preview must start paused and muted');
    }
    await (state.start() as Future<void>);
    await player.stream.position
        .firstWhere((p) => p.inMilliseconds >= 300)
        .timeout(const Duration(seconds: 10));
    scroll.jumpTo(1200);
    await Future<void>.delayed(const Duration(milliseconds: 2700));
    if (state.player != null) {
      throw StateError('Offscreen video was not released');
    }
    scroll.jumpTo(0);
    await ready();
    if ((state.player as Player).state.volume != 0 ||
        (state.player as Player).state.playing) {
      throw StateError('Restored preview mismatch');
    }
    stdout.writeln(
      jsonEncode({
        'inline_preview': 'pass',
        'paused_first_frame': true,
        'default_volume': 0,
        'offscreen_release_and_reload': true,
        'browser_used': false,
        'synthetic_only': true,
      }),
    );
    await stdout.flush();
    runApp(const SizedBox());
    await WidgetsBinding.instance.endOfFrame;
    exit(0);
  } catch (e) {
    stderr.writeln('Inline preview check failed: ${e.runtimeType}');
    exit(1);
  }
}

/// Explicit CLI check using a supplied synthetic clip. Does not load user data.
Future<void> runVideoSelfCheck(String fixture) async {
  Player? player;
  try {
    if (!fixture.endsWith('.mp4') || !await File(fixture).exists()) {
      throw StateError('Synthetic MP4 missing');
    }
    MediaKit.ensureInitialized();
    player = Player(configuration: const PlayerConfiguration(muted: true));
    final controller = VideoController(player);
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 640,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Video(controller: controller),
              ),
            ),
          ),
        ),
      ),
    );
    await player.setVolume(0);
    await player.open(Media(File(fixture).absolute.path), play: true);
    final native = await controller.platform.future;
    await native.waitUntilFirstFrameRendered.timeout(
      const Duration(seconds: 15),
    );
    await player.stream.position
        .firstWhere((p) => p.inMilliseconds >= 300)
        .timeout(const Duration(seconds: 15));
    if (player.state.volume != 0 || controller.id.value == null) {
      throw StateError('Video output or mute mismatch');
    }
    await player.pause();
    await player.seek(const Duration(seconds: 2));
    stdout.writeln(
      jsonEncode({
        'native_video_texture': 'pass',
        'first_frame_rendered': true,
        'decoded_width': player.state.videoParams.w,
        'volume': player.state.volume,
        'play_pause_seek': true,
        'browser_used': false,
        'synthetic_only': true,
      }),
    );
    await stdout.flush();
    runApp(const SizedBox());
    await WidgetsBinding.instance.endOfFrame;
    await player.dispose();
    exit(0);
  } catch (e) {
    stderr.writeln('Native video check failed: ${e.runtimeType}');
    await player?.dispose();
    exit(1);
  }
}
