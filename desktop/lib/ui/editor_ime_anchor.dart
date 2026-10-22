import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Complements the Windows engine's composing rectangle with the actual caret.
/// No text or credentials leave Dart; the native channel receives only geometry.
class EditorImeAnchor extends StatefulWidget {
  final FocusNode focusNode;
  final TextEditingController controller;
  final Widget child;
  const EditorImeAnchor({
    super.key,
    required this.focusNode,
    required this.controller,
    required this.child,
  });
  @override
  State<EditorImeAnchor> createState() => _EditorImeAnchorState();
}

class _EditorImeAnchorState extends State<EditorImeAnchor> {
  static const channel = MethodChannel('moe.cangku.xingyu/editor_ime');
  bool pending = false;
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(changed);
    widget.controller.addListener(changed);
    changed();
  }

  @override
  void didUpdateWidget(EditorImeAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(changed);
      widget.focusNode.addListener(changed);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(changed);
      widget.controller.addListener(changed);
    }
    changed();
  }

  Future<void> send(String method, [Object? args]) async {
    try {
      await channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      /* Widget tests and other platforms. */
    } on PlatformException {
      /* A closing window has no active IME context. */
    }
  }

  void changed() {
    if (!supported) return;
    if (!widget.focusNode.hasFocus) {
      unawaited(send('clearCaret'));
      return;
    }
    if (pending) return;
    pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      pending = false;
      if (!mounted || !widget.focusNode.hasFocus) return;
      EditableTextState? editable;
      void visit(Element element) {
        if (element is StatefulElement && element.state is EditableTextState) {
          editable = element.state as EditableTextState;
          return;
        }
        element.visitChildren(visit);
      }

      context.visitChildElements(visit);
      final render = editable?.renderEditable;
      final selection = widget.controller.selection;
      if (render != null && render.attached && selection.isValid) {
        final composing = widget.controller.value.composing;
        // While composing use the beginning of that range, as Windows expects.
        final position = TextPosition(
          offset: composing.isValid && !composing.isCollapsed
              ? composing.start
              : selection.extentOffset,
        );
        final rect = render.getLocalRectForCaret(position);
        final global = MatrixUtils.transformRect(
          render.getTransformTo(null),
          rect,
        );
        if (global.isFinite) {
          unawaited(
            send('setCaret', {
              'x': global.left,
              'y': global.top,
              'width': global.width,
              'height': global.height,
            }),
          );
        }
      }
      // Run after layout on subsequent frames, including scrolling and resizing.
      // This queues a callback without creating an animation or forcing frames.
      changed();
    });
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(changed);
    widget.controller.removeListener(changed);
    if (supported && widget.focusNode.hasFocus) unawaited(send('clearCaret'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
