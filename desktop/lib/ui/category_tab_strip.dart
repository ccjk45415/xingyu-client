import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Each category level owns its scroll position and a draggable desktop thumb.
class CategoryTabStrip extends StatefulWidget {
  final List<Widget> children;
  const CategoryTabStrip({super.key, required this.children});
  @override
  State<CategoryTabStrip> createState() => _CategoryTabStripState();
}

class _CategoryTabStripState extends State<CategoryTabStrip> {
  final controller = ScrollController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !controller.hasClients) return;
    final delta = event.scrollDelta.dx == 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    final position = controller.position;
    final next = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (next == position.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (controller.hasClients) controller.jumpTo(next);
    });
  }

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: const MaterialScrollBehavior().copyWith(
      scrollbars: false,
      dragDevices: {
        PointerDeviceKind.mouse,
        PointerDeviceKind.touch,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      },
    ),
    child: Listener(
      onPointerSignal: wheel,
      child: Scrollbar(
        controller: controller,
        thumbVisibility: true,
        trackVisibility: true,
        interactive: true,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
          child: Row(children: widget.children),
        ),
      ),
    ),
  );
}
