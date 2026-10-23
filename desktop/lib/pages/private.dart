import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/platform.dart';
import '../core/media.dart';
import '../core/state.dart';
import '../ui/shared.dart';
import 'conversation.dart';

void clearPrivateDrafts() {
  _PrivatePageState.drafts.clear();
  _PrivatePageState.buffers.clear();
}

class PrivatePage extends StatefulWidget {
  final DeskRoute route;
  const PrivatePage(this.route, {super.key});
  @override
  State<PrivatePage> createState() => _PrivatePageState();
}

class _PrivatePageState extends State<PrivatePage> with WidgetsBindingObserver {
  final input = TextEditingController(),
      search = TextEditingController(),
      focus = FocusNode(),
      scroll = ScrollController();
  final SplayTreeMap<int, Json> messages = SplayTreeMap();
  Timer? poll;
  AppState? app;
  Json peer = {};
  Json? attachment, pending;
  bool active = true,
      loading = false,
      sending = false,
      uploading = false,
      available = false,
      initial = true,
      hasOlder = false;
  String error = '', query = '';
  int cursor = 0, revision = 0, lastRead = 0;
  static final Map<String, String> drafts = {};
  static final Map<String, Json> buffers = {};
  int owner = 0;
  String get draftKey => '$owner:${widget.route.id}';
  @override
  void initState() {
    super.initState();
    query = widget.route.query;
    search.text = query;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (app == null) {
      app = stateOf(context);
      owner = app!.uid;
      final saved = buffers[draftKey] ?? {};
      input.text = text(saved['text'], drafts[draftKey] ?? '');
      attachment = saved['image'] is Map ? object(saved['image']) : null;
      pending = saved['pending'] is Map ? object(saved['pending']) : null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && app!.verified) unawaited(start());
      });
    }
  }

  Future<void> start() async {
    if (!mounted || !active || !app!.verified) return;
    poll?.cancel();
    unawaited(app!.syncProfile().catchError((Object _) {}));
    if (widget.route.kind == 'dm') await loadThread(first: initial);
    if (!mounted || !active) return;
    poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || !active || !app!.verified) return;
      if (widget.route.kind == 'dm') {
        unawaited(loadThread());
      } else if (widget.route.kind == 'inbox' && widget.route.id == 0) {
        setState(() => revision++);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active) {
      unawaited(start());
    } else {
      poll?.cancel();
    }
  }

  @override
  void dispose() {
    if (app != null && app!.uid == owner) {
      drafts[draftKey] = input.text;
      buffers[draftKey] = {
        'text': input.text,
        'image': attachment,
        'pending': pending,
      };
    }
    poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    input.dispose();
    search.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  bool valid(int owner) => mounted && active && app!.uid == owner;
  Future<void> loadThread({bool first = false, bool older = false}) async {
    if (loading || !app!.verified) return;
    loading = true;
    final owner = app!.uid, target = widget.route.id;
    try {
      if (first) {
        final r = await app!.service.request(
          '/dm/v1/peer?id=$target',
          token: app!.token,
        );
        if (!valid(owner)) return;
        available = r['available'] == true;
        peer = object(r['user']);
        if (!available) {
          setState(() {
            initial = false;
            error = '这位作者尚未开通星屿私信，暂时无法收信。';
          });
          return;
        }
      }
      var more = false, loops = 0;
      do {
        final suffix = older && messages.isNotEmpty
            ? '&before=${messages.firstKey()}'
            : first
            ? ''
            : '&after=$cursor';
        final r = await app!.service.request(
          '/dm/v1/messages?peer=$target$suffix',
          token: app!.token,
        );
        if (!valid(owner)) return;
        peer = object(r['peer']);
        final all = rows(r['messages']);
        for (final row in all) {
          messages[number(row['id'])] = row;
        }
        if (!older) {
          cursor = number(r['cursor']) > cursor ? number(r['cursor']) : cursor;
        }
        if (first || older) hasOlder = r['has_older'] == true;
        while (messages.length > 300) {
          messages.remove(messages.firstKey());
        }
        more = r['has_more'] == true;
        loops++;
        if (first || older) break;
      } while (more && loops < 10);
      final received = messages.values
          .where((m) => number(m['recipient_id']) == owner)
          .map((m) => number(m['id']));
      if (received.isNotEmpty && received.last > lastRead && valid(owner)) {
        await app!.service.request(
          '/dm/v1/read',
          token: app!.token,
          body: {'peer_id': target, 'last_id': received.last},
        );
        lastRead = received.last;
      }
      if (valid(owner)) {
        final near =
            !scroll.hasClients ||
            scroll.position.maxScrollExtent - scroll.offset < 120;
        setState(() {
          initial = false;
          error = '';
        });
        if (!older && near) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && scroll.hasClients) {
              scroll.jumpTo(scroll.position.maxScrollExtent);
            }
          });
        }
      }
    } catch (e) {
      if (e is ApiFailure && e.status == 401 && valid(owner)) {
        app!.expireIdentity();
      }
      if (valid(owner)) {
        setState(() {
          error = '$e';
          initial = false;
        });
      }
    } finally {
      loading = false;
    }
  }

  Future<void> send() async {
    if (sending ||
        !available ||
        !app!.verified ||
        input.value.composing.isValid) {
      return;
    }
    if (pending == null && input.text.trim().isEmpty && attachment == null) {
      return;
    }
    if (input.text.trim().runes.length > 500) {
      message(context, '每条私信最多500字');
      return;
    }
    pending ??= {
      'peer_id': widget.route.id,
      'text': input.text.trim(),
      'client_id': nonce(),
      'image_id': attachment?['id'],
    };
    final payload = pending!, owner = app!.uid;
    setState(() => sending = true);
    try {
      final result = await app!.service.request(
        '/dm/v1/messages',
        token: app!.token,
        body: payload,
      );
      if (!valid(owner)) return;
      final row = object(result['message']);
      messages[number(row['id'])] = row;
      if (input.text.trim() == payload['text']) input.clear();
      if (attachment?['id'] == payload['image_id']) attachment = null;
      pending = null;
      error = '';
      setState(() {});
      unawaited(loadThread());
    } catch (e) {
      if (e is ApiFailure && e.status == 401 && valid(owner)) {
        app!.expireIdentity();
      }
      if (valid(owner)) setState(() => error = '$e · 可重试同一条消息');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> image() async {
    if (uploading || sending) return;
    setState(() => uploading = true);
    final owner = app!.uid;
    await action(context, () async {
      final bytes = await pickJpeg(context);
      if (bytes == null || !valid(owner)) return;
      final value = await uploadChatImage(
        app!,
        bytes,
        'dm',
        '${widget.route.id}',
      );
      if (valid(owner)) setState(() => attachment = value);
    });
    if (mounted) setState(() => uploading = false);
  }

  Future<void> block(int id, bool value) async {
    if (!await confirm(
          context,
          value ? '拒收这位用户？' : '解除拒收？',
          value ? '双方将不能继续互发私信，已有消息仍可查看。' : '解除后，双方可以再次发送私信。',
        ) ||
        !mounted) {
      return;
    }
    await action(context, () async {
      await app!.service.request(
        '/dm/v1/block',
        token: app!.token,
        body: {'peer_id': id, 'blocked': value},
      );
      if (mounted) setState(() => revision++);
    }, success: value ? '已拒收' : '已解除拒收');
  }

  Widget listing(BuildContext context) {
    final kind = widget.route.kind, who = app!.uid;
    return AsyncPane(
      key: ValueKey(query),
      refreshToken: revision,
      load: () {
        if (kind == 'dmPeople') {
          if (query.isEmpty) return Future.value({'data': []});
          if (RegExp(r'^[1-9][0-9]{0,12}$').hasMatch(query)) {
            return app!
                .get('user/info', {'id': query})
                .then(
                  (r) => {
                    'data': [r['data']],
                  },
                );
          }
          return app!.get('user/list', {
            'search': query,
            'page': widget.route.page,
            'per_page': 20,
          });
        }
        return app!.service.request(
          kind == 'dmBlocks'
              ? '/dm/v1/blocks'
              : '/dm/v1/conversations${widget.route.id > 0 ? '?before=${widget.route.id}' : ''}',
          token: app!.token,
        );
      },
      builder: (r, reload) {
        final all = kind == 'dmPeople'
            ? rows(r['data']).where((u) => number(u['id']) != who).toList()
            : kind == 'dmBlocks'
            ? rows(r['users'])
            : rows(r['conversations']);
        return PageBody(
          width: 1050,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Heading(
                kind == 'dmPeople'
                    ? '选择收信人'
                    : kind == 'dmBlocks'
                    ? '拒收名单'
                    : '独立私信',
                '仅在前台接收消息 · 历史保留7天 · 双方需开通',
                trailing: IconButton(
                  tooltip: '刷新会话',
                  onPressed: reload,
                  icon: const Icon(Icons.refresh),
                ),
              ),
              if (kind == 'inbox') ...[
                Wrap(
                  spacing: 14,
                  children: [
                    FilledButton.icon(
                      onPressed: () => openRoute(
                        context,
                        const DeskRoute('dmPeople', '选择收信人'),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('发一封新私信'),
                    ),
                    OutlinedButton(
                      onPressed: () => openRoute(
                        context,
                        const DeskRoute('dmBlocks', '拒收名单'),
                      ),
                      child: const Text('拒收名单'),
                    ),
                  ],
                ),
                const SizedBox(height: 25),
              ],
              if (kind == 'dmPeople') ...[
                TextField(
                  controller: search,
                  onSubmitted: (s) => setState(() => query = s.trim()),
                  decoration: InputDecoration(
                    hintText: '昵称 / UID',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => query = search.text.trim()),
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ),
                ),
                const SizedBox(height: 23),
              ],
              if (all.isEmpty)
                Blank(
                  kind == 'dmPeople' && query.isEmpty ? '想和谁聊聊？' : '暂时没有内容',
                  kind == 'dmPeople'
                      ? '搜索昵称或输入官网UID，也可以在作者主页发起私信。'
                      : '新的私信会出现在这里。',
                ),
              for (final entry in all)
                Builder(
                  builder: (c) {
                    final user = kind == 'inbox'
                            ? object(entry['peer'])
                            : entry,
                        last = object(entry['last_message']);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Surface(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 9,
                        ),
                        child: ListTile(
                          leading: Avatar(user, radius: 25),
                          title: Text(
                            '${text(user['nickname'])}${number(entry['unread']) > 0 ? '  ·  ${number(entry['unread'])} 未读' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              kind == 'inbox'
                                  ? '${last['image'] != null ? '[图片] ' : ''}${text(last['text'])}'
                                  : 'UID ${number(user['id'])}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          trailing: kind == 'dmBlocks'
                              ? TextButton(
                                  onPressed: () =>
                                      block(number(user['id']), false),
                                  child: const Text('解除拒收'),
                                )
                              : const Icon(Icons.chevron_right),
                          onTap: kind == 'dmBlocks'
                              ? null
                              : () => openRoute(
                                  context,
                                  DeskRoute('dm', '私信', id: number(user['id'])),
                                ),
                        ),
                      ),
                    );
                  },
                ),
              if (kind == 'dmPeople')
                Pagination(
                  r,
                  widget.route.page,
                  (p) => openRoute(
                    context,
                    DeskRoute('dmPeople', '选择收信人', query: query, page: p),
                  ),
                ),
              if (r['has_more'] == true && kind == 'inbox')
                TextButton(
                  onPressed: () => openRoute(
                    context,
                    DeskRoute(
                      'inbox',
                      '更多会话',
                      id: number(object(all.last['last_message'])['id']),
                    ),
                  ),
                  child: const Text('加载更早的会话'),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => IdentityGate(
    onReady: () => unawaited(start()),
    child: widget.route.kind != 'dm'
        ? listing(context)
        : initial
        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
        : !available
        ? Blank(
            '暂时不能开始私信',
            error,
            button: FilledButton.tonal(
              onPressed: () => unawaited(loadThread(first: true)),
              child: const Text('重新检查'),
            ),
          )
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 18,
                ),
                child: Row(
                  children: [
                    Avatar(
                      peer,
                      onTap: () => openRoute(
                        context,
                        DeskRoute('author', '作者主页', id: widget.route.id),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            text(peer['nickname']),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                          Text(
                            'UID ${widget.route.id}',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => block(widget.route.id, true),
                      child: const Text('拒收'),
                    ),
                    IconButton(
                      onPressed: () => unawaited(loadThread()),
                      tooltip: '刷新私信',
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Scrollbar(
                  controller: scroll,
                  child: ListView(
                    controller: scroll,
                    padding: const EdgeInsets.all(28),
                    children: [
                      if (hasOlder && messages.length < 300)
                        Center(
                          child: TextButton(
                            onPressed: loading
                                ? null
                                : () => unawaited(loadThread(older: true)),
                            child: const Text('加载更早的私信'),
                          ),
                        ),
                      if (messages.isEmpty)
                        const Blank('第一封信，从这里开始。', '只有你与收信人可以读取这段对话。'),
                      for (final m in messages.values)
                        MessageBubble(
                          messageData: m,
                          user: number(m['sender_id']) == app!.uid
                              ? app!.user!
                              : peer,
                          mine: number(m['sender_id']) == app!.uid,
                          onName: () => openRoute(
                            context,
                            DeskRoute(
                              'author',
                              '作者主页',
                              id: number(m['sender_id']),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(26, 14, 26, 23),
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  children: [
                    if (error.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    if (attachment != null)
                      Row(
                        children: [
                          const Text(
                            '已添加图片',
                            style: TextStyle(fontSize: 11, color: violet),
                          ),
                          IconButton(
                            onPressed: sending
                                ? null
                                : () => setState(() => attachment = null),
                            icon: const Icon(Icons.close, size: 16),
                          ),
                        ],
                      ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: uploading || sending ? null : image,
                          tooltip: '发送图片',
                          icon: Icon(
                            uploading
                                ? Icons.hourglass_top
                                : Icons.image_outlined,
                          ),
                        ),
                        if (!isAndroid)
                          const Text(
                            'Enter 发送 · Shift+Enter 换行',
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        const Spacer(),
                        const Text(
                          '仅在前台同步',
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: CallbackShortcuts(
                            bindings: {
                              const SingleActivator(
                                LogicalKeyboardKey.enter,
                              ): () =>
                                  unawaited(send()),
                            },
                            child: TextField(
                              controller: input,
                              focusNode: focus,
                              enabled: !sending,
                              minLines: 2,
                              maxLines: 5,
                              maxLength: 1000,
                              decoration: InputDecoration(
                                hintText: '给 ${text(peer['nickname'])} 留言…',
                                counterText: '',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        FilledButton(
                          onPressed: sending ? null : send,
                          child: Text(
                            sending
                                ? '发送中…'
                                : pending != null
                                ? '重试'
                                : '发送',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
  );
}
