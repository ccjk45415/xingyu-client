import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api.dart';
import '../core/chat.dart';
import '../core/media.dart';
import '../ui/shared.dart';

class IdentityGate extends StatefulWidget {
  final Widget child;
  final VoidCallback? onReady;
  const IdentityGate({super.key, required this.child, this.onReady});
  @override
  State<IdentityGate> createState() => _IdentityGateState();
}

class _IdentityGateState extends State<IdentityGate> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final app = stateOf(context);
    if (app.verified) return widget.child;
    return Blank(
      '让热爱，有人回应。',
      '聊天室和私信使用仓库账号认证。\n将临时发送当前官网会话到你的聊天服务，向固定官网验证昵称、UID和头像；不发送密码、不保存官网会话。认证7天有效。\n\n私信双方都需安装星屿并开通认证，官网网页不会收到这些私信。',
      icon: Icons.verified_user_outlined,
      button: FilledButton.icon(
        onPressed: busy
            ? null
            : () async {
                if (!await confirm(
                      context,
                      '验证仓库身份？',
                      '同意临时使用官网会话核验本人账号。\n聊天与图片保留7天，只有前台接收消息；聊天服务可读取消息，传输加密不是端到端加密。',
                      action: '同意并认证',
                    ) ||
                    !context.mounted) {
                  return;
                }
                setState(() => busy = true);
                await action(context, () async {
                  await app.enableIdentity();
                  widget.onReady?.call();
                });
                if (mounted) setState(() => busy = false);
              },
        icon: const Icon(Icons.verified_outlined),
        label: Text(busy ? '正在认证…' : '认证仓库账号'),
      ),
    );
  }
}

class ChatPage extends StatefulWidget {
  final ChatController? controller;
  const ChatPage({super.key, this.controller});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  ChatController? chat;
  final input = TextEditingController(),
      focus = FocusNode(),
      scroll = ScrollController();
  bool uploading = false;
  int messageCount = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (chat == null) {
      chat = (widget.controller ?? ChatController(stateOf(context)))
        ..addListener(changed);
      unawaited(chat!.start());
    }
  }

  void changed() {
    if (!mounted) return;
    final room = chat!.room;
    if (input.text != room.draft) {
      input.value = TextEditingValue(
        text: room.draft,
        selection: TextSelection.collapsed(offset: room.draft.length),
      );
    }
    final nearBottom =
        !scroll.hasClients ||
        scroll.position.maxScrollExtent - scroll.offset < 120;
    final added = messageCount != room.messages.length;
    messageCount = room.messages.length;
    setState(() {});
    if (nearBottom && added) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.animateTo(
            scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(chat?.start());
    } else {
      chat?.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    chat?.removeListener(changed);
    if (widget.controller == null) {
      chat?.dispose();
    } else {
      chat?.pause();
    }
    input.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  void mention(Json original) {
    final c = chat!, user = c.profile(original), id = number(user['id']);
    if (c.room.sending) return;
    c.room.mentions.removeWhere(
      (uid, _) => !c.room.draft.contains('(UID:$uid)'),
    );
    if (!c.room.mentions.containsKey(id) && c.room.mentions.length >= 5) {
      message(context, '每条消息最多艾特5人');
      return;
    }
    final marker = '@${text(user['nickname'])}(UID:$id) ';
    c.room.mentions[id] = marker;
    final at = input.selection.isValid
        ? input.selection.start
        : input.text.length;
    input.value = TextEditingValue(
      text: input.text.replaceRange(at, at, marker),
      selection: TextSelection.collapsed(offset: at + marker.length),
    );
    c.room.draft = input.text;
    focus.requestFocus();
  }

  Future<void> addImage() async {
    if (uploading || !chat!.ready) return;
    final c = chat!,
        app = stateOf(context),
        room = c.room,
        selected = c.channel,
        owner = app.uid;
    setState(() => uploading = true);
    await action(context, () async {
      final bytes = await pickJpeg(context);
      if (bytes == null ||
          !mounted ||
          selected != c.channel ||
          owner != app.uid) {
        return;
      }
      final image = await uploadChatImage(app, bytes, 'chat', selected);
      if (mounted && selected == c.channel && owner == app.uid) {
        room.image = image;
        c.update();
      }
    });
    if (mounted) setState(() => uploading = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = chat;
    if (c == null) return const SizedBox.shrink();
    final app = stateOf(context), room = c.room;
    return IdentityGate(
      onReady: () => unawaited(c.start()),
      child: Row(
        children: [
          Container(
            width: 205,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: .65),
              border: Border(
                right: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 9),
                  const Text(
                    '一起聊点喜欢的',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '两个频道，各聊各的。',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 28),
                  for (final channel in ['1', '2'])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 13),
                      child: Material(
                        color: c.channel == channel
                            ? violet.withValues(alpha: .12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          leading: Icon(
                            Icons.tag,
                            color: c.channel == channel ? violet : Colors.grey,
                          ),
                          title: Text(
                            '频道${channel == '1' ? '一' : '二'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: const Text(
                            '独立消息空间',
                            style: TextStyle(fontSize: 10),
                          ),
                          onTap: () {
                            input.clear();
                            unawaited(c.choose(channel));
                          },
                        ),
                      ),
                    ),
                  const Spacer(),
                  const Icon(Icons.verified_outlined, color: violet, size: 20),
                  const SizedBox(height: 10),
                  const Text(
                    '仓库账号认证\n昵称、UID、头像来自官网',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                      height: 1.9,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 25,
                    vertical: 18,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.tag, color: violet),
                      const SizedBox(width: 10),
                      Text(
                        '频道${c.channel == '1' ? '一' : '二'}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => unawaited(c.start()),
                        icon: Icon(
                          c.ready ? Icons.circle : Icons.refresh,
                          size: c.ready ? 7 : 16,
                          color: c.ready ? const Color(0xff72ad96) : violet,
                        ),
                        label: const Text('重新连接'),
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
                      padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
                      children: [
                        if (room.older && room.messages.length < 300)
                          Center(
                            child: TextButton(
                              onPressed: room.loading
                                  ? null
                                  : () => action(context, c.older),
                              child: Text(room.loading ? '加载中…' : '加载更早的消息'),
                            ),
                          ),
                        if (room.messages.isEmpty)
                          const Blank('这里还很安静', '点击头像或名字可以艾特，消息下方可以引用回复。'),
                        for (final m in room.messages.values)
                          MessageBubble(
                            messageData: m,
                            user: c.profile(object(m['sender'])),
                            mine: number(object(m['sender'])['id']) == app.uid,
                            tagged:
                                rows(
                                  m['mentions'],
                                ).any((p) => number(p['id']) == app.uid) ||
                                number(
                                      object(
                                        object(m['reply_to'])['sender'],
                                      )['id'],
                                    ) ==
                                    app.uid,
                            onName: () => mention(object(m['sender'])),
                            onReply: () {
                              room.reply = m;
                              c.update();
                              focus.requestFocus();
                            },
                            profile: c.profile,
                          ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(25, 12, 25, 20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(
                      top: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (room.reply != null)
                        _QuoteBar(
                          '回复 ${text(c.profile(object(room.reply!['sender']))['nickname'])}：${text(room.reply!['text'], '[图片]')}',
                          () {
                            room.reply = null;
                            c.update();
                          },
                        ),
                      if (room.image != null)
                        _QuoteBar('已添加图片 · 发送后保留7天', () {
                          room.image = null;
                          c.update();
                        }),
                      Row(
                        children: [
                          IconButton(
                            onPressed: c.ready && !room.sending && !uploading
                                ? addImage
                                : null,
                            tooltip: '发送图片',
                            icon: Icon(
                              uploading
                                  ? Icons.hourglass_top
                                  : Icons.image_outlined,
                              size: 22,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              c.status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          const Text(
                            'Enter 发送 · Shift+Enter 换行',
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: CallbackShortcuts(
                              bindings: {
                                const SingleActivator(
                                  LogicalKeyboardKey.enter,
                                ): () {
                                  if (!input.value.composing.isValid) c.send();
                                },
                                const SingleActivator(
                                  LogicalKeyboardKey.enter,
                                  control: true,
                                ): c.send,
                              },
                              child: TextField(
                                controller: input,
                                focusNode: focus,
                                enabled: !room.sending,
                                minLines: 2,
                                maxLines: 5,
                                maxLength: 600,
                                onChanged: (v) {
                                  room.draft = v;
                                },
                                decoration: const InputDecoration(
                                  hintText: '分享此刻的心情…',
                                  counterText: '',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 15),
                          FilledButton(
                            onPressed: c.ready && !room.sending ? c.send : null,
                            child: Text(
                              room.sending
                                  ? '发送中…'
                                  : room.pending != null
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
          ),
        ],
      ),
    );
  }
}

class _QuoteBar extends StatelessWidget {
  final String label;
  final VoidCallback remove;
  const _QuoteBar(this.label, this.remove);
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.only(left: 13),
    decoration: BoxDecoration(
      color: violet.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ),
        IconButton(onPressed: remove, icon: const Icon(Icons.close, size: 15)),
      ],
    ),
  );
}

class MessageBubble extends StatelessWidget {
  final Json messageData, user;
  final bool mine, tagged;
  final VoidCallback? onName, onReply;
  final Json Function(Json)? profile;
  const MessageBubble({
    super.key,
    required this.messageData,
    required this.user,
    required this.mine,
    this.tagged = false,
    this.onName,
    this.onReply,
    this.profile,
  });
  @override
  Widget build(BuildContext context) {
    final reply = object(messageData['reply_to']),
        original = object(reply['sender']),
        quote = profile?.call(original) ?? original;
    final details = Column(
      crossAxisAlignment: mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onName,
          child: Text(
            '${mine ? '我 · ' : ''}${text(user['nickname'])}  ·  UID ${number(user['id'])}',
            style: const TextStyle(
              color: violet,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          dateText(messageData['created_at']),
          style: const TextStyle(color: Colors.grey, fontSize: 9),
        ),
        if (tagged)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('有人提到了你', style: TextStyle(color: pink, fontSize: 11)),
          ),
        const SizedBox(height: 8),
        if (reply.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: violet.withValues(alpha: .07),
              border: const Border(left: BorderSide(color: violet, width: 2)),
            ),
            child: Text(
              '回复 ${text(quote['nickname'])}：${reply['has_image'] == true ? '[图片] ' : ''}${text(reply['text'])}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, height: 1.6),
            ),
          ),
        if (messageData['image'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: ChatImage(object(messageData['image'])),
          ),
        if (text(messageData['text']).isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
            decoration: BoxDecoration(
              color: mine ? violet : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(mine ? 16 : 4),
                bottomRight: Radius.circular(mine ? 4 : 16),
              ),
            ),
            child: SelectableText(
              text(messageData['text']),
              style: TextStyle(
                fontSize: 14,
                height: 1.7,
                color: mine ? Colors.white : null,
              ),
            ),
          ),
        if (onReply != null)
          TextButton(
            onPressed: onReply,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            ),
            child: const Text('回复', style: TextStyle(fontSize: 10)),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: LayoutBuilder(
        builder: (c, box) => Row(
          mainAxisAlignment: mine
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine) ...[
              Avatar(user, radius: 18, onTap: onName),
              const SizedBox(width: 12),
            ],
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (box.maxWidth - 80).clamp(100, 650),
              ),
              child: details,
            ),
            if (mine) ...[
              const SizedBox(width: 12),
              Avatar(user, radius: 18, onTap: onName),
            ],
          ],
        ),
      ),
    );
  }
}
