import 'dart:async';

import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;

import '../core/api.dart';
import '../core/state.dart';
import 'cached_image.dart';
import 'shared.dart';

DateTime? lotteryTime(dynamic value) {
  final raw = text(value).trim();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(
    RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(raw)
        ? raw
        : '${raw.replaceFirst(' ', 'T')}+08:00',
  );
}

bool lotteryCanEnter(Json detail, DateTime now) =>
    detail.isNotEmpty &&
    detail['participated'] != true &&
    detail['is_finished'] != true &&
    detail['is_published'] != true &&
    !(lotteryTime(detail['start_at'])?.isAfter(now) ?? false) &&
    !(lotteryTime(detail['end_at'])?.isBefore(now) ?? false);

/// Official state and endpoints; never executes article scripts or retries a POST.
class ArticleLottery extends StatefulWidget {
  final int id;
  const ArticleLottery(this.id, {super.key});
  @override
  State<ArticleLottery> createState() => _ArticleLotteryState();
}

class _ArticleLotteryState extends State<ArticleLottery> {
  AppState? app;
  int owner = -1, revision = 0;
  Json detail = {};
  bool loading = true, busy = false;
  String error = '';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = stateOf(context);
    if (app != next || owner != next.uid) {
      app = next;
      owner = next.uid;
      detail = {};
      busy = false;
      unawaited(load());
    }
  }

  @override
  void didUpdateWidget(covariant ArticleLottery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      detail = {};
      busy = false;
      unawaited(load());
    }
  }

  bool current(int job, int uid) =>
      mounted && revision == job && app!.uid == uid;
  Future<Json> fetch() async => object(
    (await app!.site.get('lottery/info', {
      'id': widget.id,
      if (owner > 0) 'include': 'participated',
    }))['data'],
  );

  Future<void> load() async {
    final job = ++revision, uid = owner;
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final data = await fetch();
      if (!mounted || !current(job, uid)) return;
      if (number(data['id']) != widget.id) {
        throw const FormatException('Invalid lottery');
      }
      setState(() => detail = data);
    } catch (_) {
      if (current(job, uid)) setState(() => error = '抽奖信息暂时无法加载，请重试');
    } finally {
      if (current(job, uid)) setState(() => loading = false);
    }
  }

  Future<void> participate() async {
    if (busy || loading) return;
    if (owner <= 0) {
      message(context, '登录后才可以参与抽奖');
      return;
    }
    final job = revision, uid = owner;
    setState(() => busy = true);
    var submitted = false;
    try {
      // Re-read live state before asking about the actual cost.
      final fresh = await fetch();
      if (!mounted || !current(job, uid)) return;
      if (number(fresh['id']) != widget.id) {
        throw const FormatException('Invalid lottery');
      }
      setState(() => detail = fresh);
      if (!lotteryCanEnter(fresh, DateTime.now())) return;
      final cost = number(fresh['point']);
      if (!await confirm(
            context,
            '参与抽奖？',
            '${text(fresh['name'], '抽奖活动')}\n${cost > 0 ? '将扣除 $cost 点积分。' : '本次参与无需积分。'}',
            action: '确认参与',
          ) ||
          !current(job, uid)) {
        return;
      }
      if (!lotteryCanEnter(fresh, DateTime.now())) return;
      submitted = true;
      await app!.site.post('lottery/participate', {'id': '${widget.id}'});
      if (!mounted || !current(job, uid)) return;
      setState(() => detail = {...detail, 'participated': true});
      message(context, '参与成功');
    } catch (_) {
      if (!mounted || !current(job, uid)) return;
      // An interrupted response may already have charged points. Reconcile with
      // the official state once, without repeating the participation request.
      if (submitted) {
        try {
          final fresh = await fetch();
          if (!mounted || !current(job, uid)) return;
          if (number(fresh['id']) == widget.id) setState(() => detail = fresh);
        } catch (_) {
          /* Keep the last state and offer a manual refresh. */
        }
      }
      if (mounted && current(job, uid)) {
        message(
          context,
          detail['participated'] == true ? '官网已确认参与成功' : '操作结果暂未确认，请刷新抽奖状态后再试',
        );
      }
    } finally {
      if (current(job, uid)) setState(() => busy = false);
    }
  }

  Future<void> winners() async {
    if (busy) return;
    final job = revision, uid = owner;
    setState(() => busy = true);
    try {
      final result = await app!.site.get('lottery/winners', {
        'id': widget.id,
        'all': 1,
        'with[0]': 'user',
        'include': 'user',
      });
      if (!mounted || !current(job, uid)) return;
      final prizes = rows(detail['prizes']), groups = <int, List<String>>{};
      for (final winner in rows(result['data'])) {
        final name = text(object(winner['user'])['nickname']);
        if (name.isNotEmpty) (groups[number(winner['prize'])] ??= []).add(name);
      }
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('中奖用户'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Text(
                groups.isEmpty
                    ? '暂未公布中奖用户'
                    : groups.entries
                          .map(
                            (entry) =>
                                '${entry.key >= 0 && entry.key < prizes.length ? text(prizes[entry.key]['name']) : '奖品'}：${entry.value.join('，')}',
                          )
                          .join('\n\n'),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted && current(job, uid)) message(context, '中奖结果暂时无法加载，请稍后重试');
    } finally {
      if (current(job, uid)) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final upcoming =
        lotteryTime(detail['start_at'])?.isAfter(DateTime.now()) ?? false;
    final ended =
        detail['is_finished'] == true ||
        (lotteryTime(detail['end_at'])?.isBefore(DateTime.now()) ?? false);
    final published = detail['is_published'] == true;
    final entered = detail['participated'] == true;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                Icon(Icons.card_giftcard_outlined, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text(detail['name'], '抽奖活动'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: loading || busy ? null : load,
                  tooltip: '刷新抽奖状态',
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(error),
                  TextButton(onPressed: load, child: const Text('重新加载')),
                ],
              ),
            )
          else ...[
            if (safeExternal(text(detail['background'])))
              SizedBox(
                height: 160,
                child: CachedImage(
                  text(detail['background']),
                  fit: BoxFit.cover,
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (text(detail['description']).isNotEmpty) ...[
                    Text(
                      html.parseFragment(text(detail['description'])).text ??
                          '',
                    ),
                    const SizedBox(height: 12),
                  ],
                  for (final prize in rows(detail['prizes']))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          if (safeExternal(text(prize['image']))) ...[
                            SizedBox(
                              width: 42,
                              height: 42,
                              child: CachedImage(
                                text(prize['image']),
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Text(
                              '${text(prize['name'])} × ${number(prize['count'])}',
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    '${number(detail['participant_count'])} 人参与 · ${number(detail['point'])} 积分',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  if (text(detail['end_at']).isNotEmpty)
                    Text(
                      '截止：${text(detail['end_at'])}',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  const SizedBox(height: 14),
                  if (upcoming)
                    Text('尚未开始 · ${text(detail['start_at'])}')
                  else if (ended && !published)
                    const Text('抽奖已结束，请等待开奖结果'),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: busy
                          ? null
                          : published
                          ? winners
                          : lotteryCanEnter(detail, DateTime.now())
                          ? participate
                          : null,
                      icon: Icon(
                        entered
                            ? Icons.check_rounded
                            : Icons.card_giftcard_outlined,
                        size: 19,
                      ),
                      label: Text(
                        busy
                            ? '正在确认…'
                            : published
                            ? '查看中奖用户'
                            : entered
                            ? '已参与'
                            : '参与抽奖',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
