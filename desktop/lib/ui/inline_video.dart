import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/ai.dart';
import '../core/api.dart' show siteOrigin;
import '../core/error_diagnostics.dart';
import '../core/platform.dart';
import 'cached_image.dart';

const articleVideoConfiguration = PlayerConfiguration(
  title: '星屿 · 正文视频',
  muted: true,
  bufferSize: 16 * 1024 * 1024,
  protocolWhitelist: [
    'https',
    'http',
    'httpproxy',
    'tcp',
    'tls',
    'crypto',
    'data',
  ],
);

/// Lazy native playback: no browser, no automatic requests for unopened videos.
class InlineArticleVideo extends StatefulWidget {
  final String url, poster, title, sourceUrl;
  final bool preload;
  final Future<String> Function(String)? mediaResolver;
  final Player Function()? playerFactory;
  const InlineArticleVideo({
    super.key,
    required this.url,
    this.poster = '',
    this.title = '作品视频',
    this.sourceUrl = '',
    this.preload = true,
    this.mediaResolver,
    this.playerFactory,
  });
  @override
  State<InlineArticleVideo> createState() => _InlineArticleVideoState();
}

class _InlineArticleVideoState extends State<InlineArticleVideo>
    with WidgetsBindingObserver {
  static final _active = <_InlineArticleVideoState>{};
  Player? player;
  VideoController? controller;
  AiTransport? transport;
  StreamSubscription<String>? errors;
  StreamSubscription<bool>? playing;
  ScrollPosition? scroll;
  bool busy = false, previewAttempted = false, firstFrame = false;
  bool visibilityQueued = false;
  bool userRequestedPlay = false;
  Timer? releaseTimer;
  String? error;
  int revision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    queueVisibility();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Scrollable.maybeOf(context)?.position;
    if (scroll != next) {
      scroll?.removeListener(onScroll);
      scroll = next;
      scroll?.addListener(onScroll);
    }
    queueVisibility();
  }

  bool get visible {
    if (!mounted) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final bounds = box.localToGlobal(Offset.zero) & box.size;
    var viewport = Offset.zero & MediaQuery.sizeOf(context);
    final scrollBox = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (scrollBox is RenderBox && scrollBox.hasSize) {
      viewport = viewport.intersect(
        scrollBox.localToGlobal(Offset.zero) & scrollBox.size,
      );
    }
    final area = bounds.intersect(viewport);
    return area.width > 0 && area.height > 20;
  }

  void onScroll() => queueVisibility();
  void queueVisibility() {
    if (visibilityQueued) return;
    visibilityQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      visibilityQueued = false;
      if (!mounted) return;
      if (visible) {
        releaseTimer?.cancel();
        releaseTimer = null;
        if (widget.preload && !previewAttempted) {
          previewAttempted = true;
          unawaited(prepare());
        }
      } else {
        unawaited(player?.pause());
        releaseTimer ??= Timer(const Duration(seconds: 2), () {
          releaseTimer = null;
          if (!mounted || visible) return;
          revision++;
          release();
          setState(() {
            busy = false;
            firstFrame = false;
            previewAttempted = false;
          });
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(player?.pause());
  }

  @override
  void didUpdateWidget(covariant InlineArticleVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url) {
      revision++;
      busy = false;
      error = null;
      release();
      previewAttempted = false;
      firstFrame = false;
      queueVisibility();
    }
  }

  void release() {
    transport?.close();
    transport = null;
    unawaited(errors?.cancel());
    unawaited(playing?.cancel());
    errors = null;
    playing = null;
    final old = player;
    player = null;
    controller = null;
    _active.remove(this);
    if (old != null) unawaited(old.dispose());
  }

  Future<void> start() => prepare(play: true);
  Future<void> prepare({bool play = false}) async {
    if (play) userRequestedPlay = true;
    if (busy) return;
    if (player != null && firstFrame && error == null) {
      if (play) await player!.play();
      return;
    }
    userRequestedPlay = play;
    previewAttempted = true;
    var step = 'article-video-resolve';
    final job = ++revision;
    release();
    setState(() {
      busy = true;
      error = null;
      firstFrame = false;
    });
    try {
      final io = transport = AiTransport();
      final url =
          await (widget.mediaResolver?.call(widget.url) ??
              io.playableVideo(widget.url));
      if (!mounted || job != revision) return;
      step = 'article-video-initialize';
      MediaKit.ensureInitialized();
      final next = player =
          widget.playerFactory?.call() ??
          Player(configuration: articleVideoConfiguration);
      controller = VideoController(next);
      // Native initialization waits for the next Flutter frame, including
      // when an embedded player URL was resolved after the loading frame.
      setState(() {});
      errors = next.stream.error.listen((_) {
        if (mounted && job == revision) {
          unawaited(next.pause());
          setState(() {
            error = '视频加载失败，请检查网络后重试';
            busy = false;
          });
        }
      });
      playing = next.stream.playing.listen((value) {
        if (value && (!busy || userRequestedPlay)) {
          for (final other in _active.toList()) {
            if (other != this) unawaited(other.player?.pause());
          }
        }
      });
      _active.add(this);
      if (nativeMediaProxy.isNotEmpty && next.platform is NativePlayer) {
        await (next.platform as NativePlayer).setProperty(
          'http-proxy',
          nativeMediaProxy,
        );
      }
      await next.setVolume(0);
      final base = Uri.tryParse(widget.sourceUrl)?.scheme == 'https'
          ? Uri.parse(widget.sourceUrl)
          : Uri.parse(siteOrigin);
      step = 'article-video-open';
      await next.open(
        Media(
          url,
          httpHeaders: {
            'Referer': '${base.origin}/',
            'User-Agent': 'Mozilla/5.0 Xingyu-Article-Video/1',
          },
        ),
        // Some demuxers do not deliver a texture while opened paused. Decode
        // the first frame silently, then pause immediately for the preview.
        play: true,
      );
      if (!mounted || job != revision) return;
      step = 'article-video-first-frame';
      final output = await controller!.platform.future.timeout(
        const Duration(seconds: 25),
      );
      await output.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 25),
      );
      if (!mounted || job != revision) return;
      if (!userRequestedPlay ||
          !visible ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
        await next.pause();
        // Keep the preview at the beginning, without consuming the clip.
        if (!userRequestedPlay) await next.seek(Duration.zero);
      }
      if (!mounted || job != revision) return;
      setState(() {
        busy = false;
        firstFrame = true;
      });
    } catch (failure, stack) {
      if (mounted && job == revision) {
        unawaited(appDiagnostics.record(failure, stack, step));
        release();
        setState(() {
          busy = false;
          error = '暂时无法播放此视频，请检查网络后重试';
        });
      }
    }
  }

  @override
  void dispose() {
    revision++;
    releaseTimer?.cancel();
    scroll?.removeListener(onScroll);
    WidgetsBinding.instance.removeObserver(this);
    release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 12),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (controller != null && error == null)
                Video(
                  controller: controller!,
                  resumeUponEnteringForegroundMode: false,
                ),
              if (!firstFrame || error != null)
                DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xffece3fa), Color(0xfff5edf9)],
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.poster.startsWith('https://'))
                        CachedImage(
                          widget.poster,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(
                              Icons.smart_display_outlined,
                              size: 52,
                              color: Color(0xffbba3d8),
                            ),
                          ),
                        ),
                      Center(
                        child: busy
                            ? const CircularProgressIndicator()
                            : FilledButton.icon(
                                onPressed: start,
                                icon: Icon(
                                  error == null
                                      ? Icons.play_arrow_rounded
                                      : Icons.refresh_rounded,
                                ),
                                label: Text(error == null ? '播放视频' : '重试'),
                              ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Row(
            children: [
              const Icon(Icons.smart_display_rounded, size: 20),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      error ?? '正文内播放 · 默认静音，可在播放器开启声音',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
