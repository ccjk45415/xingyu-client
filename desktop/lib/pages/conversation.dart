import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/chat.dart';
import '../core/media.dart';
import '../core/platform.dart';
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
      scroll = ScrollController(keepScrollOffset: false);
  bool uploading = false;
  int messageCount = 0;
  String displayedChannel = '';
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
    final channelChanged = displayedChannel != chat!.channel;
    displayedChannel = chat!.channel;
    final nearBottom = !scroll.hasClients || scroll.offset < 120;
    final added = messageCount != room.messages.length;
    messageCount = room.messages.length;
    setState(() {});
    if (channelChanged || nearBottom && added) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          if (channelChanged) {
            scroll.jumpTo(0);
          } else {
            scroll.animateTo(
              0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
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
    if (c.room.sending || id <= 0) return;
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
    final compact = MediaQuery.sizeOf(context).width < 760;
    final messages = room.messages.values
        .toList(growable: false)
        .reversed
        .toList(growable: false);
    return IdentityGate(
      onReady: () => unawaited(c.start()),
      child: Row(
        children: [
          if (!compact)
            Container(
              width: 205,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface
                    .withValues(alpha: .65),
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
                    const IconBadge(Icons.forum_rounded, size: 48),
                    const SizedBox(height: 18),
                    const Text(
                      '一起聊点喜欢的',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '遇见同好，分享此刻。',
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
                              color: c.channel == channel
                                  ? violet
                                  : Colors.grey,
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
                    const Icon(
                      Icons.verified_outlined,
                      color: violet,
                      size: 20,
                    ),
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
                if (compact)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: '1',
                          label: Text('频道一'),
                          icon: Icon(Icons.tag_rounded),
                        ),
                        ButtonSegment(
                          value: '2',
                          label: Text('频道二'),
                          icon: Icon(Icons.tag_rounded),
                        ),
                      ],
                      selected: {c.channel},
                      onSelectionChanged: (values) {
                        input.clear();
                        unawaited(c.choose(values.first));
                      },
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 16 : 25,
                    vertical: compact ? 8 : 18,
                  ),
                  child: Row(
                    children: [
                      IconBadge(
                        c.channel == '1'
                            ? Icons.waving_hand_outlined
                            : Icons.bubble_chart_outlined,
                        size: compact ? 36 : 42,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '频道${c.channel == '1' ? '一' : '二'}',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Text(
                              '与同好聊聊喜欢的作品',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: c.connecting
                            ? null
                            : () => unawaited(c.start(reconnect: true)),
                        icon: Icon(
                          c.ready ? Icons.circle : Icons.refresh,
                          size: c.ready ? 7 : 16,
                          color: c.ready ? const Color(0xff72ad96) : violet,
                        ),
                        label: Text(
                          c.ready
                              ? '已连接'
                              : c.connecting
                              ? '连接中'
                              : '重新连接',
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: Scrollbar(
                    controller: scroll,
                    child: ListView.builder(
                      reverse: true,
                      controller: scroll,
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 14 : 28,
                        vertical: 16,
                      ),
                      itemCount: messages.length + 1,
                      itemBuilder: (context, index) {
                        if (index == messages.length) {
                          if (room.older && messages.length < 300) {
                            return Center(
                              child: TextButton.icon(
                                onPressed: room.loading
                                    ? null
                                    : () => action(context, c.older),
                                icon: const Icon(
                                  Icons.history_rounded,
                                  size: 16,
                                ),
                                label: Text(room.loading ? '加载中…' : '加载更早的消息'),
                              ),
                            );
                          }
                          if (messages.isNotEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Surface(
                              color: violet.withValues(alpha: .045),
                              child: Column(
                                children: [
                                  const IconBadge(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 56,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    room.historyFailed
                                        ? '暂时没有连上消息'
                                        : room.historyLoaded
                                        ? '这里还很安静'
                                        : '欢迎来到聊天室',
                                    style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    room.historyFailed
                                        ? '可以重试加载，不会影响已经输入的内容。'
                                        : room.historyLoaded
                                        ? '点击头像查看作者主页，长按头像或点击名字艾特，点击回复引用消息。'
                                        : '消息正在同步，可以先写下想说的话。',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                      height: 1.7,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  if (room.historyFailed)
                                    TextButton.icon(
                                      onPressed: c.retryHistory,
                                      icon: const Icon(Icons.refresh_rounded),
                                      label: const Text('重新加载消息'),
                                    )
                                  else
                                    const Wrap(
                                      spacing: 12,
                                      runSpacing: 8,
                                      alignment: WrapAlignment.center,
                                      children: [
                                        Chip(
                                          avatar: Icon(
                                            Icons.verified_user_outlined,
                                            size: 15,
                                          ),
                                          label: Text('仓库身份认证'),
                                        ),
                                        Chip(
                                          avatar: Icon(
                                            Icons.alternate_email_rounded,
                                            size: 15,
                                          ),
                                          label: Text('长按头像艾特'),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          );
                        }
                        final m = messages[index];
                        return MessageBubble(
                          key: ValueKey('${c.channel}:${m['id']}'),
                          messageData: m,
                          user: c.profile(object(m['sender'])),
                          mine: number(object(m['sender'])['id']) == app.uid,
                          tagged:
                              rows(m['mentions'])
                                  .any((p) => number(p['id']) == app.uid) ||
                              number(
                                    object(
                                      object(m['reply_to'])['sender'],
                                    )['id'],
                                  ) ==
                                  app.uid,
                          onName: () => mention(object(m['sender'])),
                          onAvatar: () {
                            final id = number(object(m['sender'])['id']);
                            if (id <= 0) return;
                            openRoute(
                              context,
                              DeskRoute('author', '作者主页', id: id),
                            );
                          },
                          onMention: () => mention(object(m['sender'])),
                          onReply: () {
                            room.reply = m;
                            c.update();
                            focus.requestFocus();
                          },
                          profile: c.profile,
                        );
                      },
                    ),
                  ),
                ),
                Container(
                  margin: EdgeInsets.fromLTRB(
                    compact ? 8 : 20,
                    4,
                    compact ? 8 : 20,
                    compact ? 8 : 16,
                  ),
                  padding: EdgeInsets.fromLTRB(
                    compact ? 12 : 25,
                    8,
                    compact ? 12 : 25,
                    compact ? 10 : 20,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: violet.withValues(alpha: .12)),
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
                          if (!isAndroid)
                            const Text(
                              'Enter 发送 · Shift+Enter 换行',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
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
                                primaryShortcut(LogicalKeyboardKey.enter):
                                    c.send,
                              },
                              child: TextField(
                                controller: input,
                                focusNode: focus,
                                enabled: !room.sending,
                                minLines: compact ? 1 : 2,
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
        IconButton(
          tooltip: '取消引用',
          onPressed: remove,
          icon: const Icon(Icons.close, size: 15),
        ),
      ],
    ),
  );
}

class MessageBubble extends StatelessWidget {
  final Json messageData, user;
  final bool mine, tagged;
  final VoidCallback? onName, onReply, onAvatar, onMention;
  final Json Function(Json)? profile;
  const MessageBubble({
    super.key,
    required this.messageData,
    required this.user,
    required this.mine,
    this.tagged = false,
    this.onName,
    this.onReply,
    this.onAvatar,
    this.onMention,
    this.profile,
  });
  @override
  Widget build(BuildContext context) {
    final reply = object(messageData['reply_to']),
        original = object(reply['sender']),
        quote = profile?.call(original) ?? original;
    final avatar = Tooltip(
      message: onMention == null ? '查看作者主页' : '点击查看作者主页 · 长按艾特',
      // Leave the long-press gesture to mention; mouse hover still shows help.
      triggerMode: TooltipTriggerMode.manual,
      child: Avatar(
        user,
        key: ValueKey('chat-avatar:${messageData['id']}'),
        radius: 18,
        onTap: onAvatar ?? onName,
        onLongPress: onMention,
      ),
    );
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
          TextButton.icon(
            icon: const Icon(Icons.reply_rounded, size: 14),
            onPressed: onReply,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            ),
            label: const Text('回复', style: TextStyle(fontSize: 11)),
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
            if (!mine) ...[avatar, const SizedBox(width: 12)],
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (box.maxWidth - 80).clamp(100, 650),
              ),
              child: details,
            ),
            if (mine) ...[const SizedBox(width: 12), avatar],
          ],
        ),
      ),
    );
  }
}
