import 'dart:math' as math;

import 'package:flutter/material.dart';

class EditorMenuAction {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool scissors;
  const EditorMenuAction(
    this.label,
    this.icon,
    this.onPressed, {
    this.scissors = false,
  });
}

/// One bounded, scrollable menu for mouse secondary clicks and touch selection.
/// The editor owns the callbacks so every action uses the captured selection.
class EditorContextMenu extends StatefulWidget {
  final TextSelectionToolbarAnchors anchors;
  final List<EditorMenuAction> clipboard, links;
  final Map<String, List<EditorMenuAction>> groups;
  final VoidCallback onDismiss;
  const EditorContextMenu({
    super.key,
    required this.anchors,
    required this.clipboard,
    required this.links,
    required this.groups,
    required this.onDismiss,
  });
  @override
  State<EditorContextMenu> createState() => _EditorContextMenuState();
}

class _EditorContextMenuState extends State<EditorContextMenu> {
  int selected = 0;
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context),
        colors = Theme.of(context).colorScheme;
    final height = math.max(
      100.0,
      media.size.height - media.viewInsets.bottom - media.padding.vertical - 24,
    );
    final width = math.min(360.0, math.max(100.0, media.size.width - 24));
    final keys = widget.groups.keys.toList();
    Widget button(EditorMenuAction action) => TextButton(
      key: ValueKey('editor.menu.${action.label}'),
      onPressed: action.onPressed,
      style: TextButton.styleFrom(
        foregroundColor: colors.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (action.scissors)
            CustomPaint(
              size: const Size(19, 19),
              painter: _ScissorsPainter(
                action.onPressed == null ? colors.outline : colors.primary,
              ),
            )
          else
            Icon(
              action.icon,
              size: 19,
              color: action.onPressed == null ? colors.outline : colors.primary,
            ),
          const SizedBox(height: 5),
          Text(
            action.label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
    Widget grid(List<EditorMenuAction> actions, int count) => Wrap(
      children: [
        for (final action in actions)
          SizedBox(width: (width - 24) / count, child: button(action)),
      ],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        media.padding.top + 12,
        12,
        media.viewInsets.bottom + media.padding.bottom + 12,
      ),
      child: CustomSingleChildLayout(
        delegate: DesktopTextSelectionToolbarLayoutDelegate(
          anchor:
              widget.anchors.primaryAnchor - Offset(12, media.padding.top + 12),
        ),
        child: SizedBox(
          width: width,
          child: Material(
            key: const Key('editor.context.menu'),
            color: colors.surface,
            elevation: 8,
            shadowColor: colors.shadow.withValues(alpha: .18),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: colors.outlineVariant),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: math.min(480, height)),
              child: Scrollbar(
                controller: scroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: scroll,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.edit_outlined,
                            size: 17,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              '编辑正文',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            onPressed: widget.onDismiss,
                            tooltip: '关闭菜单',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ],
                      ),
                      grid(widget.clipboard, 4),
                      const Divider(height: 16),
                      grid(widget.links, 2),
                      const SizedBox(height: 8),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            for (var i = 0; i < keys.length; i++)
                              Expanded(
                                child: TextButton(
                                  key: ValueKey('editor.menu.group.${keys[i]}'),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    minimumSize: const Size(0, 40),
                                    backgroundColor: selected == i
                                        ? colors.secondaryContainer
                                        : null,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  onPressed: () => setState(() => selected = i),
                                  child: Text(
                                    keys[i],
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: selected == i
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      grid(widget.groups[keys[selected]]!, 3),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draw the small scissors in Dart so existing installations need no new font.
class _ScissorsPainter extends CustomPainter {
  final Color color;
  const _ScissorsPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 20, size.height / 20);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(const Offset(4.5, 5), 2.6, pen);
    canvas.drawCircle(const Offset(4.5, 15), 2.6, pen);
    canvas.drawLine(const Offset(6.5, 6.5), const Offset(17.5, 17.5), pen);
    canvas.drawLine(const Offset(6.5, 13.5), const Offset(17.5, 2.5), pen);
  }

  @override
  bool shouldRepaint(covariant _ScissorsPainter oldDelegate) =>
      oldDelegate.color != color;
}
