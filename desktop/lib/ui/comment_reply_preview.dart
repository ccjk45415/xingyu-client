import 'package:flutter/material.dart';

/// Keeps long threads compact without confusing cached replies with the full
/// discussion. The full discussion remains available through [onViewAll].
class CommentReplyPreview extends StatefulWidget {
  final List<Widget> replies;
  final int total;
  final VoidCallback onViewAll;
  final int previewLimit;

  const CommentReplyPreview({
    super.key,
    required this.replies,
    required this.total,
    required this.onViewAll,
    this.previewLimit = 3,
  }) : assert(previewLimit > 0);

  @override
  State<CommentReplyPreview> createState() => _CommentReplyPreviewState();
}

class _CommentReplyPreviewState extends State<CommentReplyPreview> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final loaded = widget.replies.length;
    final total = widget.total > loaded ? widget.total : loaded;
    if (total <= 0) return const SizedBox.shrink();
    final canCollapse = loaded > widget.previewLimit;
    final visible = expanded ? loaded : widget.previewLimit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...widget.replies.take(visible),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (canCollapse)
              TextButton.icon(
                key: const Key('comment.replies.toggle'),
                onPressed: () => setState(() => expanded = !expanded),
                icon: Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 19,
                ),
                label: Text(
                  expanded
                      ? '收起回复'
                      : '展开剩余 ${loaded - widget.previewLimit} 条回复',
                ),
              ),
            TextButton.icon(
              key: const Key('comment.replies.all'),
              onPressed: widget.onViewAll,
              icon: const Icon(Icons.forum_outlined, size: 17),
              label: Text('查看全部回复 · $total'),
            ),
          ],
        ),
      ],
    );
  }
}
