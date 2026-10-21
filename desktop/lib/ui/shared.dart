import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/state.dart';
import '../core/qr.dart';

const violet = Color(0xff8a6adb),
    pink = Color(0xffe797b7),
    ink = Color(0xff322c48);

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
      width: 480,
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
  } catch (e) {
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
  final VoidCallback? onTap;
  const Avatar(this.user, {super.key, this.radius = 21, this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(radius),
    onTap: onTap,
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
  return Image.network(
    url,
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
      borderRadius: BorderRadius.circular(22),
      side: BorderSide(
        color: Theme.of(context).colorScheme.outlineVariant
            .withValues(alpha: .3),
      ),
    ),
    child: Padding(padding: padding, child: child),
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
  @override
  void dispose() {
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
        controller: controller,
        padding: widget.padding,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.width),
            child: widget.child,
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    ),
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
            Icon(icon, size: 48, color: violet),
            const SizedBox(height: 20),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(subtitle, textAlign: TextAlign.center),
            if (button != null) ...[const SizedBox(height: 22), button!],
          ],
        ),
      ),
    ),
  );
}

class AsyncPane extends StatefulWidget {
  final Object? refreshToken;
  final Future<Json> Function() load;
  final Widget Function(Json, VoidCallback) builder;
  const AsyncPane({
    super.key,
    required this.load,
    required this.builder,
    this.refreshToken,
  });
  @override
  State<AsyncPane> createState() => _AsyncPaneState();
}

class _AsyncPaneState extends State<AsyncPane> {
  late Future<Json> future;
  @override
  void initState() {
    super.initState();
    future = widget.load();
  }

  @override
  void didUpdateWidget(covariant AsyncPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != oldWidget.refreshToken) future = widget.load();
  }

  void reload() {
    if (mounted) setState(() => future = widget.load());
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
    future: future,
    builder: (c, snap) {
      if (snap.hasError) {
        return Blank(
          '暂时没有连接上',
          '${snap.error}',
          icon: Icons.cloud_off_outlined,
          button: FilledButton.tonalIcon(
            onPressed: reload,
            icon: const Icon(Icons.refresh),
            label: const Text('重新加载'),
          ),
        );
      }
      if (!snap.hasData) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      return widget.builder(snap.data!, reload);
    },
  );
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
  final double? fontSize;
  const RichContent(this.html, {super.key, this.fontSize});
  @override
  Widget build(BuildContext context) => HtmlWidget(
    html,
    textStyle: TextStyle(
      fontSize: fontSize ?? stateOf(context).fontSize,
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
      if (element.localName == 'img') {
        final uri = Uri.tryParse(element.attributes['src'] ?? '');
        if (uri == null ||
            !['http', 'https'].contains(uri.scheme) ||
            uri.userInfo.isNotEmpty ||
            uri.host.isEmpty) {
          return const Text('[不支持的图片]');
        }
        final url = uri.toString();
        return QrImageActions(
          url: url,
          child: InkWell(
            onTap: () => showImage(context, url: url),
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Text('[图片暂时无法加载]'),
            ),
          ),
        );
      }
      return null;
    },
    customStylesBuilder: (element) => switch (element.localName) {
      'img' => {'max-width': '100%', 'border-radius': '12px'},
      'a' => {'color': '#9671de'},
      'pre' => {'white-space': 'pre-wrap', 'padding': '16px'},
      _ => null,
    },
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
        insetPadding: const EdgeInsets.all(40),
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
                      : Image.network(
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
                  '右键图片可识别二维码链接 · 滚轮缩放',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.pop(c),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
