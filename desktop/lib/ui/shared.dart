import 'inline_video.dart';
import 'cached_image.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/browse_cache.dart';
import '../core/state.dart';
import '../core/qr.dart';
import '../core/error_diagnostics.dart';
import '../core/platform.dart';

const violet = Color(0xff8a6adb),
    pink = Color(0xffe797b7),
    ink = Color(0xff322c48);

IconData pageIcon(String title) {
  for (final entry in <(List<String>, IconData)>[
    (['AI', '智能'], Icons.auto_awesome_rounded),
    (['诊断'], Icons.bug_report_outlined),
    (['安全', '密码', '邮箱'], Icons.shield_outlined),
    (['外观', '阅读偏好'], Icons.palette_outlined),
    (['更新'], Icons.system_update_alt_rounded),
    (['设置'], Icons.tune_rounded),
    (['通知'], Icons.notifications_none_rounded),
    (['评论', '回复', '讨论'], Icons.chat_bubble_outline_rounded),
    (['私信', '会话'], Icons.mail_outline_rounded),
    (['聊天', '频道'], Icons.forum_outlined),
    (['关注', '粉丝'], Icons.people_outline_rounded),
    (['动态'], Icons.rss_feed_rounded),
    (['分类'], Icons.dashboard_customize_outlined),
    (['排行'], Icons.local_fire_department_outlined),
    (['投稿', '草稿', '创作'], Icons.edit_note_rounded),
    (['资料', '作者', '我的'], Icons.person_outline_rounded),
    (['收藏'], Icons.bookmarks_outlined),
    (['足迹', '记录', '历史'], Icons.history_rounded),
    (['搜索'], Icons.manage_search_rounded),
    (['下载'], Icons.download_rounded),
    (['发现', '首页'], Icons.explore_outlined),
  ]) {
    if (entry.$1.any(title.contains)) return entry.$2;
  }
  return Icons.auto_stories_outlined;
}

class IconBadge extends StatelessWidget {
  final IconData icon;
  final double size;
  const IconBadge(this.icon, {super.key, this.size = 44});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * .31),
      gradient: LinearGradient(
        colors: [violet.withValues(alpha: .14), pink.withValues(alpha: .13)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      border: Border.all(color: violet.withValues(alpha: .1)),
    ),
    alignment: Alignment.center,
    child: Icon(
      icon,
      size: size * .5,
      color: Theme.of(context).colorScheme.primary,
    ),
  );
}

class DeskRoute {
  final String kind, title, query, filter;
  final int id, page;
  const DeskRoute(
    this.kind,
    this.title, {
    this.id = 0,
    this.query = '',
    this.filter = '',
    this.page = 1,
  });
  String get key => '$kind:$id:$query:$filter:$page';
  DeskRoute at(int value) =>
      DeskRoute(kind, title, id: id, query: query, filter: filter, page: value);
}

class DeskScope extends InheritedWidget {
  final AppState app;
  final void Function(DeskRoute) open;
  const DeskScope({
    super.key,
    required this.app,
    required this.open,
    required super.child,
  });
  static DeskScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DeskScope>()!;
  @override
  bool updateShouldNotify(DeskScope oldWidget) => true;
}

AppState stateOf(BuildContext c) => DeskScope.of(c).app;
void openRoute(BuildContext c, DeskRoute r) => DeskScope.of(c).open(r);
void message(BuildContext c, String text) {
  if (!c.mounted) return;
  ScaffoldMessenger.of(c).showSnackBar(
    SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      width: (MediaQuery.sizeOf(c).width - 32).clamp(0, 480),
    ),
  );
}

Future<bool> confirm(
  BuildContext c,
  String title,
  String body, {
  String action = '确认',
}) async =>
    await showDialog<bool>(
      context: c,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Text(body),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
Future<void> action(
  BuildContext c,
  Future<void> Function() work, {
  String? success,
}) async {
  try {
    await work();
    if (success != null && c.mounted) message(c, success);
  } catch (e, stack) {
    unawaited(appDiagnostics.record(e, stack, 'action'));
    if (c.mounted) message(c, '$e');
  }
}

Future<void> copy(BuildContext c, String value, [String label = '已复制']) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (c.mounted) message(c, label);
}

Future<void> openLink(BuildContext c, String url) async {
  final id = articleId(url);
  if (id > 0) {
    openRoute(c, DeskRoute('article', '作品详情', id: id));
    return;
  }
  if (!safeExternal(url)) {
    message(c, '链接格式暂不支持');
    return;
  }
  final uri = Uri.parse(url);
  if (['http', 'https'].contains(uri.scheme) &&
      RegExp(
        r'\.(?:png|jpe?g|gif|webp|bmp)$',
        caseSensitive: false,
      ).hasMatch(uri.path)) {
    await showImage(c, url: url);
    return;
  }
  try {
    if (!await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        ) &&
        c.mounted) {
      message(c, '没有可打开此链接的程序，可复制链接');
    }
  } catch (_) {
    if (c.mounted) message(c, '打开失败，可复制链接');
  }
}

String dateText(dynamic raw) {
  final d = DateTime.tryParse(text(raw))?.toLocal();
  if (d == null) return text(raw);
  String two(int n) => n.toString().padLeft(2, '0');
  final now = DateTime.now();
  return '${d.year == now.year && d.month == now.month && d.day == now.day ? '今天' : '${two(d.month)}-${two(d.day)}'} ${two(d.hour)}:${two(d.minute)}';
}

class Avatar extends StatelessWidget {
  final Json user;
  final double radius;
  final VoidCallback? onTap, onLongPress;
  const Avatar(
    this.user, {
    super.key,
    this.radius = 21,
    this.onTap,
    this.onLongPress,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(radius),
    onTap: onTap,
    onLongPress: onLongPress,
    child: ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: _image(
          text(user['avatar']),
          const Icon(Icons.person_rounded, color: violet),
          fit: BoxFit.cover,
        ),
      ),
    ),
  );
}

Widget _image(String url, Widget fallback, {BoxFit fit = BoxFit.cover}) {
  final u = Uri.tryParse(url);
  if (u == null ||
      !['https', 'http'].contains(u.scheme) ||
      u.userInfo.isNotEmpty) {
    return ColoredBox(
      color: violet.withValues(alpha: .10),
      child: Center(child: fallback),
    );
  }
  return CachedImage(
    url,
    headers: const {'Referer': '$siteOrigin/'},
    fit: fit,
    cacheWidth: 1000,
    errorBuilder: (_, _, _) => ColoredBox(
      color: violet.withValues(alpha: .10),
      child: Center(child: fallback),
    ),
    loadingBuilder: (c, child, progress) => progress == null
        ? child
        : ColoredBox(
            color: violet.withValues(alpha: .08),
            child: const Center(
              child: Icon(Icons.auto_awesome_outlined, color: violet, size: 30),
            ),
          ),
  );
}

class Cover extends StatelessWidget {
  final String url;
  final double? height;
  const Cover(this.url, {super.key, this.height});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: _image(url, const Icon(Icons.auto_awesome, color: violet, size: 34)),
  );
}

class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: color ?? Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(
        color: Theme.of(context).colorScheme.outlineVariant
            .withValues(alpha: .3),
      ),
    ),
    elevation: 1,
    shadowColor: violet.withValues(alpha: .09),
    child: Padding(
      padding:
          MediaQuery.sizeOf(context).width < 700 &&
              padding == const EdgeInsets.all(24)
          ? const EdgeInsets.all(16)
          : padding,
      child: child,
    ),
  );
}

class PageBody extends StatefulWidget {
  final Widget child;
  final double width;
  final EdgeInsets padding;
  final ScrollController? controller;
  const PageBody({
    super.key,
    required this.child,
    this.width = 1500,
    this.padding = const EdgeInsets.all(32),
    this.controller,
  });
  @override
  State<PageBody> createState() => _PageBodyState();
}

class _PageBodyState extends State<PageBody> {
  final owned = ScrollController();
  // Nested carousels/grids must never overwrite the reading viewport offset.
  final contentPositions = PageStorageBucket();
  @override
  void initState() {
    super.initState();
    (widget.controller ?? owned).addListener(rememberPosition);
  }

  @override
  void didUpdateWidget(covariant PageBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? owned).removeListener(rememberPosition);
      (widget.controller ?? owned).addListener(rememberPosition);
    }
  }

  void rememberPosition() {
    final controller = widget.controller ?? owned;
    if (!controller.keepScrollOffset || controller.positions.length != 1) {
      return;
    }
    final position = controller.position;
    if (!position.hasPixels) return;
    final storageContext = position.context.storageContext;
    PageStorage.maybeOf(storageContext)
        ?.writeState(storageContext, position.pixels);
  }

  @override
  void dispose() {
    (widget.controller ?? owned).removeListener(rememberPosition);
    owned.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller ?? owned;
    return Scrollbar(
      thumbVisibility: true,
      controller: controller,
      child: SingleChildScrollView(
        key: const PageStorageKey('page-body'),
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(),
        padding:
            MediaQuery.sizeOf(context).width < 700 &&
                widget.padding == const EdgeInsets.all(32)
            ? const EdgeInsets.all(16)
            : widget.padding,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.width),
            child: PageStorage(bucket: contentPositions, child: widget.child),
          ),
        ),
      ),
    );
  }
}

class Heading extends StatelessWidget {
  final String title, subtitle;
  final Widget? trailing;
  const Heading(this.title, this.subtitle, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 600;
      final titleBlock = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(pageIcon(title), size: compact ? 40 : 46),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: compact ? 23 : 27,
                    fontWeight: FontWeight.w800,
                    height: 1.28,
                    letterSpacing: -.35,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: compact && trailing is! IconButton
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titleBlock,
                  if (trailing != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: trailing,
                    ),
                ],
              )
            : Row(
                children: [
                  Expanded(child: titleBlock),
                  if (trailing != null) ...[
                    const SizedBox(width: 18),
                    trailing!,
                  ],
                ],
              ),
      );
    },
  );
}

class Blank extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Widget? button;
  const Blank(
    this.title,
    this.subtitle, {
    super.key,
    this.icon = Icons.nights_stay_outlined,
    this.button,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBadge(icon, size: 68),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.65,
              ),
            ),
            if (button != null) ...[const SizedBox(height: 22), button!],
          ],
        ),
      ),
    ),
  );
}

class AsyncPane extends StatefulWidget {
  final Object? refreshToken;

  /// Only public browsing pages opt in. Private drafts/messages never enter it.
  final String? cacheKey;
  final bool articlePlaceholder;
  final Future<Json> Function() load;
  final Widget Function(Json, VoidCallback) builder;
  const AsyncPane({
    super.key,
    required this.load,
    required this.builder,
    this.refreshToken,
    this.cacheKey,
    this.articlePlaceholder = false,
  });
  @override
  State<AsyncPane> createState() => _AsyncPaneState();
}

class _AsyncPaneState extends State<AsyncPane> {
  Json? shown;
  Object? error;
  bool busy = true, initialized = false;
  int request = 0, owner = 0, accountGeneration = 0;
  AppState? app;
  String? get key => widget.cacheKey == null || owner <= 0
      ? null
      : 'pane:v1:$owner:${widget.cacheKey}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context.dependOnInheritedWidgetOfExactType<DeskScope>()?.app;
    if (!initialized ||
        next?.uid != app?.uid ||
        owner != (next?.uid ?? 0) ||
        accountGeneration != (next?.generation ?? 0)) {
      app = next;
      begin();
    }
  }

  @override
  void didUpdateWidget(covariant AsyncPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != oldWidget.refreshToken ||
        widget.cacheKey != oldWidget.cacheKey) {
      begin();
    }
  }

  void begin({bool retain = false}) {
    initialized = true;
    owner = app?.uid ?? 0;
    accountGeneration = app?.generation ?? 0;
    busy = true;
    error = null;
    final snapshotKey = key;
    if (!retain) {
      final cached = snapshotKey == null
          ? null
          : BrowseCache.shared.peekJson(snapshotKey);
      shown = cached == null ? null : {...cached, '_xingyu_cache': true};
    }
    final current = ++request, epoch = BrowseCache.shared.epoch;
    unawaited(read(current, snapshotKey, epoch));
  }

  bool valid(int current) =>
      mounted &&
      current == request &&
      (app == null ||
          app!.uid == owner && app!.generation == accountGeneration);

  Future<void> read(int current, String? snapshotKey, int epoch) async {
    if (shown == null && snapshotKey != null) {
      // Disk lookup and network run independently; a slow cache never delays fresh data.
      unawaited(
        BrowseCache.shared.json(snapshotKey).then((cached) {
          if (valid(current) &&
              busy &&
              cached != null &&
              epoch == BrowseCache.shared.epoch) {
            setState(() => shown = {...cached, '_xingyu_cache': true});
          }
        }),
      );
    }
    try {
      final result = await runZoned(
        widget.load,
        zoneValues: {if (snapshotKey != null) browsingRevalidate: true},
      );
      if (!valid(current)) return;
      if (snapshotKey != null &&
          result['_xingyu_offline'] != true &&
          epoch == BrowseCache.shared.epoch) {
        unawaited(
          BrowseCache.shared.putJson(snapshotKey, result, generation: epoch),
        );
      }
      setState(() {
        shown = result;
        busy = false;
        error = null;
      });
    } catch (failure, stack) {
      unawaited(appDiagnostics.record(failure, stack, 'page-load'));
      if (!valid(current)) return;
      final transient =
          failure is IOException ||
          failure is TimeoutException ||
          failure is ApiFailure && failure.status >= 500;
      setState(() {
        busy = false;
        error = failure;
        if (transient && shown != null) {
          shown = {...shown!, '_xingyu_cache': true, '_xingyu_offline': true};
        } else {
          shown = null;
        }
      });
    }
  }

  void reload() {
    if (!mounted || busy) return;
    app?.refreshBrowsing();
    setState(() => begin(retain: true));
  }

  @override
  Widget build(BuildContext context) {
    if (shown == null) {
      if (error == null) {
        if (widget.cacheKey != null || widget.articlePlaceholder) {
          return LoadingLayout(article: widget.articlePlaceholder);
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_download_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              const Flexible(
                child: Text('正在载入内容…', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        );
      }
      return Blank(
        '暂时无法载入',
        error is ApiFailure
            ? (error as ApiFailure).message
            : '请重试；如果问题持续，可在设置中复制诊断信息。',
        icon: Icons.error_outline_rounded,
        button: FilledButton.tonalIcon(
          onPressed: reload,
          icon: const Icon(Icons.refresh),
          label: const Text('重新加载'),
        ),
      );
    }
    final content = widget.builder(shown!, reload);
    final cached = shown!['_xingyu_cache'] == true;
    if (widget.cacheKey == null && !cached) return content;
    return Column(
      children: [
        SizedBox(
          child: !cached
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        shown!['_xingyu_offline'] == true
                            ? Icons.cloud_off_outlined
                            : Icons.offline_bolt_outlined,
                        size: 15,
                        color: violet,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          shown!['_xingyu_offline'] == true
                              ? '网络暂不可用，正在显示本机缓存'
                              : busy
                              ? '已显示上次内容 · 后台更新中'
                              : '已从本机缓存载入',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      TextButton(
                        onPressed: busy ? null : reload,
                        child: Text(busy ? '更新中' : '刷新'),
                      ),
                    ],
                  ),
                ),
        ),
        Expanded(child: content),
      ],
    );
  }
}

/// Quiet, static placeholders keep navigation responsive on the first visit.
class LoadingLayout extends StatelessWidget {
  final bool article;
  const LoadingLayout({super.key, this.article = false});
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: .055);
    Widget block(double height, [double? width]) => Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
    );
    return ExcludeSemantics(
      child: PageBody(
        key: const PageStorageKey('loading-placeholder'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            block(article ? 38 : 28, 240),
            const SizedBox(height: 14),
            block(14, 170),
            const SizedBox(height: 28),
            if (article) ...[
              block(200),
              const SizedBox(height: 24),
              for (var i = 0; i < 6; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: block(14),
                ),
            ] else
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth < 600
                      ? 2
                      : constraints.maxWidth < 1000
                      ? 3
                      : 4;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 16) / columns;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 24,
                    children: [
                      for (var i = 0; i < columns * 2; i++)
                        SizedBox(
                          width: width,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              block(width * .6),
                              const SizedBox(height: 12),
                              block(14),
                              const SizedBox(height: 8),
                              block(11, width * .6),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class Pagination extends StatelessWidget {
  final Json result;
  final int page;
  final void Function(int) onPage;
  const Pagination(this.result, this.page, this.onPage, {super.key});
  @override
  Widget build(BuildContext context) {
    final pg = object(object(result['meta'])['pagination']),
        total = number(pg['total_pages']);
    if (total <= 1) return const SizedBox(height: 28);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: page > 1 ? () => onPage(page - 1) : null,
            icon: const Icon(Icons.chevron_left),
            label: const Text('上一页'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Text('$page / $total'),
          ),
          OutlinedButton.icon(
            onPressed: page < total ? () => onPage(page + 1) : null,
            icon: const Icon(Icons.chevron_right),
            label: const Text('下一页'),
          ),
        ],
      ),
    );
  }
}

class RichContent extends StatelessWidget {
  final String html;
  final bool preloadVideos;
  final double? fontSize, maxImageHeight, maxImageWidth;
  const RichContent(
    this.html, {
    super.key,
    this.preloadVideos = true,
    this.fontSize,
    this.maxImageHeight,
    this.maxImageWidth,
  });
  @override
  Widget build(BuildContext context) => HtmlWidget(
    html,
    textStyle: TextStyle(
      fontSize: fontSize ?? stateOf(context).fontSize,
      color: Theme.of(context).colorScheme.onSurface,
      height: 1.85,
    ),
    onTapUrl: (url) async {
      await openLink(context, url);
      return true;
    },
    onTapImage: (image) {
      if (image.sources.isNotEmpty) {
        final url = image.sources.first.url;
        if (safeExternal(url) &&
            ['https', 'http'].contains(Uri.tryParse(url)?.scheme)) {
          showImage(context, url: url);
        }
      }
    },
    customWidgetBuilder: (element) {
      if (element.classes.contains('xingyu-video') ||
          element.localName == 'video') {
        final url =
            element.attributes['data-url'] ??
            element.attributes['src'] ??
            element.querySelector('source')?.attributes['src'] ??
            '';
        if (!safeExternal(url) || Uri.tryParse(url)?.scheme != 'https') {
          return const SizedBox.shrink();
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxImageWidth ?? 760),
            child: InlineArticleVideo(
              key: ValueKey('article-video:$url'),
              url: url,
              preload: preloadVideos,
              sourceUrl:
                  element.attributes['data-original'] ??
                  element.attributes['data-source-url'] ??
                  '',
              poster:
                  element.attributes['data-poster'] ??
                  element.attributes['poster'] ??
                  '',
              title:
                  element.attributes['data-title'] ??
                  element.attributes['title'] ??
                  '作品视频',
            ),
          ),
        );
      }
      if ([
        'script',
        'style',
        'iframe',
        'object',
        'embed',
        'form',
      ].contains(element.localName)) {
        return const SizedBox.shrink();
      }
      if (element.classes.contains('text-rainbow')) {
        final width = MediaQuery.sizeOf(context).width;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) =>
              const LinearGradient(
                colors: [
                  Color(0xffe65c83),
                  Color(0xffbd8a20),
                  Color(0xff2e9f78),
                  Color(0xff477bd2),
                  Color(0xffa85ac4),
                ],
              ).createShader(
                Rect.fromLTWH(
                  0,
                  0,
                  bounds.width.clamp(1, width),
                  bounds.height,
                ),
              ),
          child: RichContent(
            element.innerHtml,
            fontSize: fontSize,
            maxImageHeight: maxImageHeight,
            maxImageWidth: maxImageWidth,
          ),
        );
      }
      if (element.classes.contains('text-forbidden')) {
        return _RevealText(
          element.innerHtml,
          fontSize: fontSize,
          maxImageHeight: maxImageHeight,
          maxImageWidth: maxImageWidth,
        );
      }
      if (element.localName == 'details') {
        final summary = element.querySelector('summary');
        final label = summary?.text ?? '折叠内容';
        final cloned = element.clone(true);
        cloned.querySelector('summary')?.remove();
        return ExpansionTile(
          initiallyExpanded: element.attributes.containsKey('open'),
          title: Text(label),
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: RichContent(
                cloned.innerHtml,
                fontSize: fontSize,
                maxImageHeight: maxImageHeight,
                maxImageWidth: maxImageWidth,
              ),
            ),
          ],
        );
      }
      if (element.localName == 'img') {
        final uri = Uri.tryParse(element.attributes['src'] ?? '');
        if (uri == null ||
            !['http', 'https'].contains(uri.scheme) ||
            uri.userInfo.isNotEmpty ||
            uri.host.isEmpty) {
          return const Text('[不支持的图片]');
        }
        final url = uri.toString();
        final sticker =
            element.classes.contains('xingyu-site-sticker') ||
            element.classes.contains('emoji') &&
                uri.host == 'cangku.moe' &&
                uri.path.startsWith('/images/stickers/');
        final image = CachedImage(
          url,
          headers: const {
            'Referer': '$siteOrigin/',
            'User-Agent': 'Mozilla/5.0 XingyuDesktop/$desktopVersion',
          },
          width: sticker ? 32 : null,
          height: sticker ? 32 : null,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Text(
            sticker ? (element.attributes['alt'] ?? '[表情]') : '[图片暂时无法加载]',
          ),
        );
        if (sticker) {
          return InlineCustomWidget(child: image);
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: maxImageHeight ?? double.infinity,
              maxWidth: maxImageWidth ?? double.infinity,
            ),
            child: QrImageActions(
              url: url,
              child: Tooltip(
                message: isAndroid ? '点击查看原图 · 长按识别二维码' : '点击查看原图 · 右键识别二维码',
                child: InkWell(
                  onTap: () => showImage(context, url: url),
                  child: image,
                ),
              ),
            ),
          ),
        );
      }
      return null;
    },
    customStylesBuilder: (element) {
      if (element.classes.contains('text-forbidden')) {
        return {'color': '#ffffff', 'background-color': '#262130'};
      }
      if (element.classes.contains('text-rainbow')) return {'color': '#a763c1'};
      if (element.classes.contains('xingyu-download') ||
          element.classes.contains('xingyu-external')) {
        return {
          'padding': '16px',
          'background-color': '#f1ebfc',
          'border': '1px solid #ded4f0',
          'border-radius': '12px',
        };
      }
      return switch (element.localName) {
        'img' => {'max-width': '100%', 'border-radius': '12px'},
        'a' => {'color': '#9671de'},
        'pre' => {'white-space': 'pre-wrap', 'padding': '16px'},
        _ => null,
      };
    },
  );
}

class _RevealText extends StatefulWidget {
  final String html;
  final double? fontSize, maxImageHeight, maxImageWidth;
  const _RevealText(
    this.html, {
    this.fontSize,
    this.maxImageHeight,
    this.maxImageWidth,
  });
  @override
  State<_RevealText> createState() => _RevealTextState();
}

class _RevealTextState extends State<_RevealText> {
  bool revealed = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => revealed = !revealed),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: revealed
            ? violet.withValues(alpha: .08)
            : const Color(0xff322c48),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: revealed
            ? RichContent(
                widget.html,
                fontSize: widget.fontSize,
                maxImageHeight: widget.maxImageHeight,
                maxImageWidth: widget.maxImageWidth,
              )
            : const Text(
                '点击显示隐藏文字',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
      ),
    ),
  );
}

class QrImageActions extends StatefulWidget {
  final String? url;
  final Uint8List? bytes;
  final Widget child;
  final Future<void> Function(String)? onOpen;
  const QrImageActions({
    super.key,
    this.url,
    this.bytes,
    this.onOpen,
    required this.child,
  });
  @override
  State<QrImageActions> createState() => _QrImageActionsState();
}

class _QrImageActionsState extends State<QrImageActions> {
  bool busy = false;
  Future<void> recognize() async {
    if (busy) return;
    setState(() => busy = true);
    message(context, '正在本机识别二维码…');
    try {
      final data = widget.bytes ?? await fetchQrImage(widget.url!);
      final value = await compute(decodeQr, data);
      if (!mounted) return;
      if (value == null) {
        message(context, '未识别到二维码，请尝试清晰的原图');
        return;
      }
      final chosen = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('二维码识别结果'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(child: SelectableText(value)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('关闭'),
            ),
            OutlinedButton(
              onPressed: () => copy(c, value),
              child: const Text('复制内容'),
            ),
            if (safeExternal(value))
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('打开链接'),
              ),
          ],
        ),
      );
      if (chosen == true && mounted) {
        if (widget.onOpen != null) {
          await widget.onOpen!(value);
        } else {
          await openLink(context, value);
        }
      }
    } catch (_) {
      if (mounted) message(context, '图片无法识别，请重试或使用清晰的原图');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onLongPress: busy
        ? null
        : () async {
            final selected = await showModalBottomSheet<String>(
              context: context,
              showDragHandle: true,
              builder: (c) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.qr_code_scanner_rounded),
                      title: const Text('识别二维码链接'),
                      onTap: () => Navigator.pop(c, 'qr'),
                    ),
                    if (widget.url != null)
                      ListTile(
                        leading: const Icon(Icons.link_rounded),
                        title: const Text('复制图片链接'),
                        onTap: () => Navigator.pop(c, 'copy'),
                      ),
                  ],
                ),
              ),
            );
            if (!mounted) return;
            if (selected == 'qr') await recognize();
            if (selected == 'copy' && context.mounted) {
              await copy(context, widget.url!);
            }
          },
    onSecondaryTapDown: (details) async {
      final overlay =
          Overlay.of(context).context.findRenderObject()! as RenderBox;
      final action = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(
            details.globalPosition.dx,
            details.globalPosition.dy,
            0,
            0,
          ),
          Offset.zero & overlay.size,
        ),
        items: [
          PopupMenuItem(
            value: 'qr',
            enabled: !busy,
            child: Text(busy ? '正在识别…' : '识别二维码链接'),
          ),
          if (widget.url != null)
            const PopupMenuItem(value: 'copy', child: Text('复制图片链接')),
        ],
      );
      if (!mounted) return;
      if (action == 'qr') await recognize();
      if (action == 'copy' && context.mounted) await copy(context, widget.url!);
    },
    child: widget.child,
  );
}

Future<void> showImage(BuildContext c, {String? url, Uint8List? bytes}) =>
    showDialog<void>(
      context: c,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.all(isAndroid ? 8 : 40),
        child: Stack(
          children: [
            Positioned.fill(
              child: QrImageActions(
                url: url,
                bytes: bytes,
                onOpen: (value) async {
                  if (articleId(value) > 0) Navigator.pop(dialogContext);
                  if (c.mounted) await openLink(c, value);
                },
                child: InteractiveViewer(
                  minScale: .3,
                  maxScale: 5,
                  child: bytes != null
                      ? Image.memory(bytes, fit: BoxFit.contain)
                      : CachedImage(
                          url!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  '图片暂时无法加载',
                                  style: TextStyle(color: Colors.white),
                                ),
                                const SizedBox(height: 15),
                                TextButton(
                                  onPressed: () => copy(c, url),
                                  child: const Text('复制图片链接'),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ),
            Positioned(
              bottom: 10,
              left: 10,
              child: IgnorePointer(
                child: Text(
                  isAndroid ? '长按识别二维码 · 双指缩放' : '右键图片可识别二维码链接 · 滚轮缩放',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton.filledTonal(
                tooltip: '关闭图片',
                onPressed: () => Navigator.pop(c),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
