import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api.dart';
import 'core/state.dart';
import 'core/updates.dart';
import 'core/chat.dart';
import 'core/platform.dart';
import 'core/error_diagnostics.dart';
import 'core/skin.dart';
import 'pages/discovery.dart';
import 'pages/quick_feed.dart';
import 'pages/dynamic_templates.dart';
import 'pages/reading.dart';
import 'pages/account.dart';
import 'pages/following.dart';
import 'pages/conversation.dart';
import 'pages/private.dart';
import 'pages/authoring.dart';
import 'ui/glass.dart';
import 'ui/shared.dart';
import 'ui/skin_panel.dart';
import 'pages/diagnostics.dart';
import 'pages/notification_settings.dart';
import 'pages/network_settings.dart';
import 'ui/windows_close.dart';

class XingyuApp extends StatelessWidget {
  final AppState app;
  XingyuApp({super.key, required this.app});
  final navigatorKey = GlobalKey<NavigatorState>();
  ThemeData theme(Brightness brightness) =>
      buildXingyuTheme(app.skin, brightness, fontFamily: uiFont);

  @override
  Widget build(BuildContext context) => WindowsCloseHost(
    app: app,
    navigatorKey: navigatorKey,
    child: AnimatedBuilder(
      animation: app,
      builder: (_, _) => MaterialApp(
        navigatorKey: navigatorKey,
        title: '仓库 · 星屿',
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          scrollbars: false,
        ),
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
        themeMode: app.dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: app.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: GlassBackdrop(child: child ?? const SizedBox.shrink()),
        ),
        home: app.starting
            ? const Scaffold(
                body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : app.user == null
            ? LoginPage(app)
            : DesktopShell(app, key: ValueKey(app.uid)),
      ),
    ),
  );
}

class LoginPage extends StatefulWidget {
  final AppState app;
  const LoginPage(this.app, {super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final account = TextEditingController(), password = TextEditingController();
  bool keep = false, hidden = true, busy = false;
  String error = '';
  Future<void> submit() async {
    if (busy) return;
    if (account.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = '请填写账号和密码');
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await widget.app.login(account.text, password.text, keep);
      password.clear();
    } catch (e, stack) {
      unawaited(appDiagnostics.record(e, stack, 'login'));
      if (mounted) setState(() => error = '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  void dispose() {
    account.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (c, size) {
          final wide = size.maxWidth > 1050;
          final form = ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 410),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: violet, size: 33),
                    SizedBox(width: 13),
                    Text(
                      '星屿',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'XINGYU',
                      style: TextStyle(
                        letterSpacing: 3,
                        color: violet,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 44),
                Text(
                  '欢迎回到你的小宇宙',
                  style: Theme.of(c).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                const Text(
                  '登录仓库账号，让喜欢在这里相遇。',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 34),
                const Text('账号', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('login.account'),
                  controller: account,
                  enabled: !busy,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(
                    hintText: '用户名 / 邮箱',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 22),
                const Text('密码', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('login.password'),
                  controller: password,
                  enabled: !busy,
                  obscureText: hidden,
                  autocorrect: false,
                  enableSuggestions: false,
                  onSubmitted: (_) => submit(),
                  decoration: InputDecoration(
                    hintText: '请输入密码',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => hidden = !hidden),
                      tooltip: '显示或隐藏密码',
                      icon: Icon(
                        hidden
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Checkbox(
                      value: keep,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => keep = v ?? false),
                    ),
                    const Text('保持登录'),
                    const Spacer(),
                    TextButton(
                      onPressed: () => openLink(context, '$siteOrigin/login'),
                      child: const Text('前往官网'),
                    ),
                  ],
                ),
                if (error.isNotEmpty || widget.app.startupError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      error.isNotEmpty ? error : widget.app.startupError!,
                      style: TextStyle(
                        color: Theme.of(c).colorScheme.error,
                        height: 1.6,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('login.submit'),
                    onPressed: busy ? null : submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(busy ? '正在连接仓库…' : '登录，开启探索  →'),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '非官方客户端 · 密码不保存在本机\n保持登录的会话由 $secureStorageLabel 保护',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 11,
                    height: 1.8,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DeskScope(
                        app: widget.app,
                        open: (_) {},
                        child: Scaffold(
                          appBar: AppBar(title: const Text('网络与代理')),
                          body: const NetworkSettingsPage(),
                        ),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.wifi_tethering_rounded, size: 17),
                  label: const Text('网络与代理'),
                ),
                TextButton.icon(
                  onPressed: () => showDiagnostics(context),
                  icon: const Icon(Icons.bug_report_outlined, size: 17),
                  label: const Text('诊断信息'),
                ),
              ],
            ),
          );
          return Row(
            children: [
              if (wide)
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xffa38bdc),
                              Color(0xffc5b5e7),
                              Color(0xffebc9df),
                            ],
                          ),
                        ),
                        child: Stack(
                          children: [
                            const Positioned.fill(
                              child: CustomPaint(painter: UniversePainter()),
                            ),
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(42),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'YOUR LITTLE UNIVERSE',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        letterSpacing: 3,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 35),
                                    const Text(
                                      '把热爱，\n收藏成星光。',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 48,
                                        fontWeight: FontWeight.w800,
                                        height: 1.5,
                                        letterSpacing: 3,
                                      ),
                                    ),
                                    const SizedBox(height: 30),
                                    const Text(
                                      '在熟悉的仓库，发现新的故事。\n为每一次心动，留一处安静的角落。',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        height: 2,
                                      ),
                                    ),
                                    const SizedBox(height: 58),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: .18,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.white30,
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.desktop_windows_rounded,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                          SizedBox(width: 14),
                                          Text(
                                            'XINGYU  /  DESKTOP EDITION',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              letterSpacing: 2,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(
                flex: 5,
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: wide ? 55 : 24,
                    vertical: 32,
                  ),
                  child: Center(
                    child: AutofillGroup(
                      child: XingyuSkinTheme.of(c).usesGlassChrome
                          ? GlassPanel(
                              borderRadius: XingyuSkinTheme.of(c).isLiquid
                                  ? 32
                                  : 28,
                              blurSigma: XingyuSkinTheme.of(c).blurSigma,
                              padding: EdgeInsets.all(wide ? 32 : 22),
                              child: form,
                            )
                          : form,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class DesktopShell extends StatefulWidget {
  final AppState app;
  const DesktopShell(this.app, {super.key});
  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell>
    with WidgetsBindingObserver {
  late final ChatController sharedChat = ChatController(widget.app);
  DeskRoute route = const DeskRoute('home', '发现');
  final List<DeskRoute> history = [];
  final readingPositions = <String, PageStorageBucket>{};
  final search = TextEditingController(), searchFocus = FocusNode();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.app.notices.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          offerStartupUpdate(
            context,
            application: widget.app,
          ).catchError((_) {}),
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.app.checkin.setWindowVisible(true);
      unawaited(refreshSystemProxy());
      unawaited(widget.app.checkin.automatic(force: true));
      unawaited(widget.app.clientConfig.refresh());
      unawaited(widget.app.patches.check());
      widget.app.notices.start();
    } else if ((!isAndroid && state == AppLifecycleState.inactive) ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.app.notices.pause();
      if (state != AppLifecycleState.inactive) {
        widget.app.checkin.setWindowVisible(false);
      }
    }
  }

  void open(DeskRoute next) {
    if (next.kind == 'chat' && ['1', '2'].contains(next.filter)) {
      unawaited(sharedChat.choose(next.filter));
    }
    if (next.key == route.key) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      history.add(route);
      route = next;
    });
  }

  void tab(DeskRoute next) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      history.clear();
      route = next;
    });
  }

  void back() {
    if (history.isNotEmpty) setState(() => route = history.removeLast());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.app.notices.pause(notify: false);
    sharedChat.dispose();
    search.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  static const navigation = [
    (Icons.explore_outlined, '首页', 'home'),
    (Icons.bolt_rounded, '快撸', 'quickFeed'),
    (Icons.interests_outlined, '分类', 'categories'),
    (Icons.local_fire_department_outlined, '排行', 'rank'),
    (Icons.forum_outlined, '聊天室', 'chat'),
    (Icons.rss_feed_rounded, '动态', 'followingFeed'),
    (Icons.person_outline_rounded, '我的', 'mine'),
  ];

  Future<void> mobileSearch() async {
    final value = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('搜索作品与作者'),
        content: TextField(
          controller: search,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: '作品标题、关键词或作者'),
          onSubmitted: (v) => Navigator.pop(c, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, search.text.trim()),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
    if (mounted && value != null && value.isNotEmpty) {
      open(DeskRoute('search', '搜索', query: value));
    }
  }

  void _openSkinPanel(BuildContext c) {
    unawaited(
      showSkinPanel(
        c,
        widget.app,
        onOpenMoreAppearance: () => open(const DeskRoute('appearance', '阅读与外观')),
      ),
    );
  }

  Widget mobile(BuildContext c) {
    final root = navigation.any((n) => n.$3 == route.kind) && history.isEmpty;
    final skin = XingyuSkinTheme.of(c);
    final glass = skin.usesGlassChrome;
    final liquid = skin.isLiquid;
    final accent = Theme.of(c).colorScheme.primary;
    final headerContent = SizedBox(
      height: 58,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            if (!root)
              IconButton(
                tooltip: '返回',
                onPressed: back,
                icon: const Icon(Icons.arrow_back_rounded),
              )
            else
              Padding(
                padding: const EdgeInsets.only(left: 6, right: 10),
                child: Icon(Icons.auto_awesome_rounded, color: accent),
              ),
            Expanded(
              child: Text(
                root && route.kind == 'home' ? '星屿' : route.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (route.kind != 'editor')
              IconButton(
                tooltip: '搜索作品与作者',
                onPressed: mobileSearch,
                icon: const Icon(Icons.search_rounded),
              ),
            IconButton(
              key: const Key('shell.skinButton'),
              tooltip: '皮肤与外观',
              onPressed: () => _openSkinPanel(c),
              icon: const Icon(Icons.palette_outlined),
            ),
            NoticeBell(
              notices: widget.app.notices,
              onPressed: () =>
                  open(const DeskRoute('noticeCenter', '消息提醒')),
            ),
          ],
        ),
      ),
    );

    final navRow = Row(
      children: [
        for (final n in navigation)
          Expanded(
            child: Semantics(
              selected: route.kind == n.$3,
              button: true,
              child: InkWell(
                key: ValueKey('mobile.nav.${n.$3}'),
                borderRadius: BorderRadius.circular(glass ? 16 : 0),
                onTap: () => tab(DeskRoute(n.$3, n.$2)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 46,
                        height: 30,
                        decoration: BoxDecoration(
                          gradient: route.kind == n.$3 && glass
                              ? LinearGradient(colors: skin.accentGradient)
                              : null,
                          color: route.kind == n.$3
                              ? (glass ? null : accent.withValues(alpha: .14))
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          n.$1,
                          size: 22,
                          color: route.kind == n.$3
                              ? (glass ? Colors.white : accent)
                              : Theme.of(c).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        n.$2,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: route.kind == n.$3
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: route.kind == n.$3
                              ? accent
                              : Theme.of(c).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    return PopScope(
      canPop: history.isEmpty && route.kind == 'home',
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (history.isNotEmpty) {
            back();
          } else {
            tab(const DeskRoute('home', '首页'));
          }
        }
      },
      child: SafeArea(
        child: Column(
          children: [
            if (glass)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: GlassPanel(
                  borderRadius: liquid ? 28 : 20,
                  blurSigma: skin.blurSigma,
                  child: headerContent,
                ),
              )
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Theme.of(c).dividerColor),
                  ),
                ),
                child: headerContent,
              ),
            Expanded(child: page()),
            if (root && MediaQuery.viewInsetsOf(c).bottom == 0)
              if (glass)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                  child: GlassPanel(
                    borderRadius: liquid ? 30 : 24,
                    blurSigma: skin.blurSigma,
                    strong: true,
                    child: navRow,
                  ),
                )
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(c).colorScheme.surface,
                    border: Border(
                      top: BorderSide(color: Theme.of(c).dividerColor),
                    ),
                  ),
                  child: navRow,
                ),
          ],
        ),
      ),
    );
  }

  Widget page() => PageStorage(
    bucket: readingPositions.putIfAbsent(route.key, PageStorageBucket.new),
    child: switch (route.kind) {
      'home' ||
      'posts' ||
      'search' ||
      'rank' ||
      'favorites' ||
      'authorPosts' => PostListPage(route, key: ValueKey(route.key)),
      'followingFeed' => FollowingFeedPage(route, key: ValueKey(route.key)),
      'quickFeed' => QuickFeedPage(
        widget.app.quickFeed,
        key: ValueKey(route.key),
      ),
      'dynamicTemplates' => DynamicTemplatesPage(
        widget.app,
        key: ValueKey(route.key),
        onOpenDraft: (taskId, snapshot, postId) async {
          final owner = widget.app.uid;
          final generation = widget.app.generation;
          final data = <String, dynamic>{...snapshot};
          if (postId > 0) {
            final latest = object(
              (await widget.app.get('post/info', {
                'id': postId,
                'include': 'user,categories:simple,tags',
                'exclude_view': 1,
              }))['data'],
            );
            if (number(latest['user_id']) != owner) {
              throw ApiFailure(403, '只能修改自己的投稿');
            }
            data['baseline'] = text(snapshot['baseline']).isNotEmpty
                ? snapshot['baseline']
                : postFingerprint(latest);
            data['version'] = text(snapshot['version']).isNotEmpty
                ? snapshot['version']
                : latest['updated_at'];
            data['oldStatus'] = latest['status'];
          }
          if (!mounted ||
              widget.app.uid != owner ||
              widget.app.generation != generation) {
            return;
          }
          final key = 'dynamic-$taskId';
          await widget.app.saveDraft(key, data, owner: owner);
          if (mounted &&
              widget.app.uid == owner &&
              widget.app.generation == generation) {
            open(DeskRoute('editor', '模板投稿预览', id: postId, query: key));
          }
        },
      ),
      'followPeople' => FollowPeoplePage(route, key: ValueKey(route.key)),
      'categories' => CategoryPage(key: ValueKey(route.key)),
      'networkSettings' => const NetworkSettingsPage(),
      'noticeSettings' => const NotificationSettingsPage(),
      'noticeCenter' => const NoticeCenterPage(),
      'article' => ArticlePage(
        route.id,
        ownerOnly: route.filter == 'private-preview',
        key: ValueKey(route.key),
      ),
      'author' => AuthorPage(route.id, key: ValueKey(route.key)),
      'chat' => ChatPage(
        key: ValueKey('chat:${widget.app.uid}'),
        controller: sharedChat,
      ),
      'dm' ||
      'inbox' ||
      'dmPeople' ||
      'dmBlocks' => PrivatePage(route, key: ValueKey(route.key)),
      'manage' ||
      'editor' ||
      'drafts' => AuthoringPage(route, key: ValueKey(route.key)),
      _ => AccountPage(route, key: ValueKey(route.key)),
    },
  );
  @override
  Widget build(BuildContext context) {
    widget.app.notices.route = route.kind;
    widget.app.notices.routeId = route.id;
    widget.app.notices.channel = sharedChat.channel;
    return DeskScope(
      app: widget.app,
      open: open,
      child: CallbackShortcuts(
        bindings: {
          primaryShortcut(LogicalKeyboardKey.keyK): () =>
              searchFocus.requestFocus(),
          if (isMacOS)
            primaryShortcut(LogicalKeyboardKey.bracketLeft): back
          else
            const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
                back,
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: NoticeOverlay(
              notices: widget.app.notices,
              child: LayoutBuilder(
                builder: (c, constraints) {
                  final full = constraints.maxWidth >= 1120;
                  final short = constraints.maxHeight < 760;
                  if (constraints.maxWidth < 700 ||
                      isAndroid && constraints.maxWidth < 1000) {
                    return mobile(c);
                  }
                  final selected =
                      [
                        'article',
                        'posts',
                        'author',
                        'authorPosts',
                        'search',
                      ].contains(route.kind)
                      ? 'home'
                      : [
                          'followPeople',
                          'inbox',
                          'dm',
                          'dmPeople',
                          'dmBlocks',
                          'settings',
                          'profile',
                          'security',
                          'appearance',
                          'updates',
                          'favorites',
                          'notifications',
                          'noticeCenter',
                          'noticeSettings',
                          'myComments',
                          'history',
                          'manage',
                          'editor',
                          'drafts',
                          'dynamicTemplates',
                          'logs',
                        ].contains(route.kind)
                      ? 'mine'
                      : route.kind;
                  final skin = XingyuSkinTheme.of(c);
                  final glass = skin.usesGlassChrome;
                  final liquid = skin.isLiquid;
                  final accent = Theme.of(c).colorScheme.primary;
                  final sidebarInner = Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          full ? 24 : 16,
                          short ? 18 : 28,
                          16,
                          short ? 18 : 30,
                        ),
                        child: Row(
                          children: [
                            if (glass)
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    liquid ? 19 : 13,
                                  ),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: skin.accentGradient,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: skin.accent.withValues(alpha: .35),
                                      blurRadius: 14,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  liquid
                                      ? Icons.bubble_chart_outlined
                                      : Icons.auto_awesome_rounded,
                                  size: 21,
                                  color: Colors.white,
                                ),
                              )
                            else
                              const Icon(
                                Icons.auto_awesome_rounded,
                                size: 31,
                                color: violet,
                              ),
                            if (full) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '星屿',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 23,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      liquid
                                          ? 'LIQUID GLASS'
                                          : glass
                                          ? 'FROST GLASS'
                                          : 'YOUR LITTLE UNIVERSE',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 7.5,
                                        letterSpacing: 1.0,
                                        fontWeight: glass
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: accent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (full)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(26, 0, 0, 12),
                            child: Text(
                              liquid
                                  ? '液态水镜 · 灵动折射'
                                  : glass
                                  ? '星光琉璃 · 探索所爱'
                                  : '探索你的喜欢',
                              style: TextStyle(
                                color: Theme.of(c).colorScheme.onSurfaceVariant,
                                fontSize: 10,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ),
                      for (final nav in [
                        (Icons.grid_view_rounded, '发现', 'home'),
                        (Icons.bolt_rounded, '快撸', 'quickFeed'),
                        (Icons.interests_outlined, '分类', 'categories'),
                        (
                          Icons.local_fire_department_outlined,
                          '排行',
                          'rank',
                        ),
                        (Icons.forum_outlined, '聊天室', 'chat'),
                        (Icons.rss_feed_rounded, '动态', 'followingFeed'),
                        (Icons.person_outline_rounded, '我的', 'mine'),
                      ])
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: full ? 14 : 11,
                            vertical: 4,
                          ),
                          child: Tooltip(
                            message: nav.$2,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  liquid ? 999 : (glass ? 16 : 14),
                                ),
                                gradient: selected == nav.$3 && glass
                                    ? LinearGradient(
                                        colors: [
                                          skin.accent.withValues(
                                            alpha: skin.isDark ? .34 : .18,
                                          ),
                                          skin.accentSecondary.withValues(
                                            alpha: skin.isDark ? .24 : .14,
                                          ),
                                        ],
                                      )
                                    : null,
                                color: selected == nav.$3
                                    ? (glass
                                          ? null
                                          : violet.withValues(alpha: .12))
                                    : Colors.transparent,
                                border: selected == nav.$3 && glass
                                    ? Border.all(
                                        color: liquid
                                            ? skin.glassBorder
                                            : skin.accent.withValues(
                                                alpha: skin.isDark ? .45 : .35,
                                              ),
                                      )
                                    : null,
                              ),
                              child: Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                  liquid ? 999 : (glass ? 16 : 14),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(
                                    liquid ? 999 : (glass ? 16 : 14),
                                  ),
                                  onTap: () => tab(DeskRoute(nav.$3, nav.$2)),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: full ? 14 : 13,
                                      vertical: 11,
                                    ),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 30,
                                          height: 30,
                                          child: selected == nav.$3
                                              ? (glass
                                                    ? Container(
                                                        decoration:
                                                            BoxDecoration(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    10,
                                                                  ),
                                                              gradient:
                                                                  LinearGradient(
                                                                    colors: skin
                                                                        .accentGradient,
                                                                  ),
                                                            ),
                                                        child: Icon(
                                                          nav.$1,
                                                          size: 17,
                                                          color: Colors.white,
                                                        ),
                                                      )
                                                    : IconBadge(
                                                        nav.$1,
                                                        size: 30,
                                                      ))
                                              : Icon(
                                                  nav.$1,
                                                  size: 22,
                                                  color: Theme.of(c)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                        ),
                                        if (full) ...[
                                          const SizedBox(width: 14),
                                          Text(
                                            nav.$2,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: selected == nav.$3
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              color: selected == nav.$3
                                                  ? accent
                                                  : null,
                                            ),
                                          ),
                                          const Spacer(),
                                          if (selected == nav.$3)
                                            Icon(
                                              Icons.circle,
                                              size: 6,
                                              color: accent,
                                            ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const Spacer(),
                      if (full && !short)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                          child: Surface(
                            padding: const EdgeInsets.all(14),
                            color: glass
                                ? (skin.isDark
                                      ? Colors.white.withValues(alpha: .06)
                                      : Colors.white.withValues(alpha: .55))
                                : violet.withValues(alpha: .065),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  liquid
                                      ? Icons.bubble_chart_outlined
                                      : glass
                                      ? Icons.auto_awesome_mosaic_rounded
                                      : Icons.nightlight_round,
                                  color: accent,
                                  size: 19,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  liquid
                                      ? '水光流转 · 晶莹视界'
                                      : glass
                                      ? '琉璃光影 · 轻盈沉浸'
                                      : '留一点时间给热爱',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  liquid
                                      ? '清澈折射，灵动随心漫游。'
                                      : glass
                                      ? '通透视界，自在漫游星屿。'
                                      : '慢慢探索，自在阅读。',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(c)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (!glass) const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                        child: Container(
                          decoration: glass
                              ? BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: skin.isDark
                                      ? Colors.white.withValues(alpha: .06)
                                      : Colors.white.withValues(alpha: .52),
                                  border: Border.all(
                                    color: skin.glassBorder,
                                    width: .9,
                                  ),
                                )
                              : null,
                          child: InkWell(
                            onTap: () =>
                                tab(const DeskRoute('mine', '我的星屿')),
                            borderRadius: BorderRadius.circular(
                              glass ? 16 : 12,
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(glass ? 8 : 2),
                              child: Row(
                                children: [
                                  Avatar(widget.app.user ?? {}, radius: 19),
                                  if (full) ...[
                                    const SizedBox(width: 11),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            text(widget.app.user?['nickname']),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            'UID ${widget.app.uid}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Theme.of(c)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.unfold_more,
                                      size: 16,
                                      color: Theme.of(c)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );

                  final headerRow = Row(
                    children: [
                      if (history.isNotEmpty)
                        IconButton(
                          onPressed: back,
                          tooltip: '返回 $backShortcutLabel',
                          icon: const Icon(Icons.arrow_back, size: 20),
                        ),
                      if (constraints.maxWidth > 1000)
                        Padding(
                          padding: const EdgeInsets.only(right: 24),
                          child: Text(
                            route.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 490),
                          child: TextField(
                            controller: search,
                            focusNode: searchFocus,
                            onSubmitted: (v) {
                              if (v.trim().isNotEmpty) {
                                open(
                                  DeskRoute(
                                    'search',
                                    '搜索',
                                    query: v.trim(),
                                  ),
                                );
                              }
                            },
                            decoration: InputDecoration(
                              hintText: '搜索作品、关键词…',
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                size: 20,
                              ),
                              suffixIcon: Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Text(
                                  '$primaryModifierLabel K',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(c)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 15,
                                vertical: 15,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      NoticeBell(
                        notices: widget.app.notices,
                        onPressed: () =>
                            open(const DeskRoute('noticeCenter', '消息提醒')),
                      ),
                      IconButton(
                        key: const Key('shell.skinButton'),
                        onPressed: () => _openSkinPanel(c),
                        tooltip: '皮肤与外观',
                        icon: const Icon(Icons.palette_outlined),
                      ),
                      IconButton(
                        onPressed: () =>
                            open(const DeskRoute('settings', '设置')),
                        tooltip: '设置',
                        icon: const Icon(Icons.settings_outlined, size: 21),
                      ),
                    ],
                  );

                  return Row(
                    children: [
                      if (glass)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 0, 14),
                          child: SizedBox(
                            width: full ? 228 : 84,
                            child: GlassPanel(
                              borderRadius: liquid ? 30 : 26,
                              blurSigma: skin.blurSigma,
                              child: sidebarInner,
                            ),
                          ),
                        )
                      else
                        Container(
                          width: full ? 222 : 86,
                          decoration: BoxDecoration(
                            color: Theme.of(c).colorScheme.surface,
                            border: Border(
                              right: BorderSide(
                                color: Theme.of(c).dividerColor,
                              ),
                            ),
                          ),
                          child: sidebarInner,
                        ),
                      Expanded(
                        child: Column(
                          children: [
                            if (glass)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  14,
                                  14,
                                  6,
                                ),
                                child: GlassPanel(
                                  borderRadius: liquid ? 28 : 22,
                                  blurSigma: skin.blurSigma,
                                  child: Container(
                                    height: 74,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 22,
                                    ),
                                    child: headerRow,
                                  ),
                                ),
                              )
                            else
                              Container(
                                height: 83,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 26,
                                ),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Theme.of(c).dividerColor,
                                    ),
                                  ),
                                ),
                                child: headerRow,
                              ),
                            Expanded(child: page()),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
