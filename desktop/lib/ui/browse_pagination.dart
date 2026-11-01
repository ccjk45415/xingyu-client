import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';

int browsePageCount(Json result) {
  final pagination = object(object(result['meta'])['pagination']);
  final pages = number(pagination['total_pages']);
  return pages < 1 ? 1 : pages;
}

/// The browse lists share one accessible jump control without changing the
/// pagination used in conversations, management, or article replies.
class BrowsePagination extends StatefulWidget {
  final Json result;
  final int page;
  final ValueChanged<int> onPage;

  const BrowsePagination(this.result, this.page, this.onPage, {super.key});

  @override
  State<BrowsePagination> createState() => _BrowsePaginationState();
}

class _BrowsePaginationState extends State<BrowsePagination> {
  late final input = TextEditingController(text: '${widget.page}');
  String? error;

  @override
  void didUpdateWidget(covariant BrowsePagination oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.page != oldWidget.page) {
      input.text = '${widget.page}';
      error = null;
    } else if (browsePageCount(widget.result) !=
        browsePageCount(oldWidget.result)) {
      error = null;
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void jump() {
    final total = browsePageCount(widget.result);
    final next = int.tryParse(input.text.trim());
    if (next == null || next < 1 || next > total) {
      setState(() => error = '请输入 1–$total 页');
      return;
    }
    setState(() => error = null);
    FocusManager.instance.primaryFocus?.unfocus();
    if (next != widget.page) widget.onPage(next);
  }

  @override
  Widget build(BuildContext context) {
    final total = browsePageCount(widget.result);
    if (total <= 1) return const SizedBox(height: 28);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: const Key('browse.pagination'),
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 460;
          final navigation = Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const Key('browse.page.previous'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                onPressed: widget.page > 1
                    ? () => widget.onPage(widget.page - 1)
                    : null,
                icon: const Icon(Icons.chevron_left_rounded, size: 18),
                label: const Text('上一页'),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    '第 ${widget.page} / $total 页',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              OutlinedButton.icon(
                key: const Key('browse.page.next'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                onPressed: widget.page < total
                    ? () => widget.onPage(widget.page + 1)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded, size: 18),
                label: const Text('下一页'),
              ),
            ],
          );
          final jumpControl = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('跳至', style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: TextField(
                  key: const Key('browse.page.input'),
                  controller: input,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.go,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 9,
                  decoration: InputDecoration(
                    counterText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 12,
                    ),
                    hintText: '页码',
                    semanticCounterText: '输入目标页码，最多 $total 页',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (_) {
                    if (error != null) setState(() => error = null);
                  },
                  onSubmitted: (_) => jump(),
                ),
              ),
              const SizedBox(width: 8),
              Text('页', style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(width: 10),
              FilledButton.tonal(
                key: const Key('browse.page.jump'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  minimumSize: const Size(64, 44),
                ),
                onPressed: jump,
                child: const Text('前往'),
              ),
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (narrow) ...[
                Center(child: navigation),
                const SizedBox(height: 12),
                Center(child: jumpControl),
              ] else
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 24,
                  runSpacing: 12,
                  children: [navigation, jumpControl],
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.error, fontSize: 12),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
