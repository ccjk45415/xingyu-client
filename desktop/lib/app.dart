import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api.dart';
import 'core/state.dart';
import 'core/updates.dart';
import 'core/chat.dart';
import 'core/platform.dart';
import 'pages/discovery.dart';
import 'pages/reading.dart';
import 'pages/account.dart';
import 'pages/following.dart';
import 'pages/conversation.dart';
import 'pages/private.dart';
import 'pages/authoring.dart';
import 'ui/shared.dart';
import 'pages/diagnostics.dart';
import 'pages/notification_settings.dart';

class XingyuApp extends StatelessWidget {
  final AppState app;
  const XingyuApp({super.key, required this.app});
  ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: violet,
          brightness: brightness,
        ).copyWith(
          primary: violet,
          secondary: pink,
          surface: dark ? const Color(0xff252232) : Colors.white,
          onSurface: dark ? const Color(0xffeee8fb) : ink,
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: uiFont,
      fontFamilyFallback: const ['Segoe UI', 'Microsoft YaHei'],
      scaffoldBackgroundColor: dark
          ? const Color(0xff1b1926)
          : const Color(0xfff8f7fc),
      visualDensity: VisualDensity.standard,
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 21),
      textTheme: const TextTheme(
        titleLarge: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.45,
        ),
        bodyLarge: TextStyle(fontSize: 15, height: 1.65),
        bodyMedium: TextStyle(fontSize: 14, height: 1.6),
        bodySmall: TextStyle(fontSize: 12, height: 1.5),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: .1,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 350),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: dark ? const Color(0xffeee7fc) : const Color(0xff3e3458),
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: TextStyle(color: dark ? ink : Colors.white, fontSize: 12),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(42, 42),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          foregroundColor: scheme.onSurfaceVariant,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 42),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: TextStyle(
            fontFamily: uiFont,
            fontFamilyFallback: ['Segoe UI', 'Microsoft YaHei'],
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xff302b40) : const Color(0xfff5f2fb),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(violet.withValues(alpha: .45)),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(7),
      ),
      dividerColor: scheme.outlineVariant.withValues(alpha: .35),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (_, _) => MaterialApp(
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
        child: child ?? const SizedBox.shrink(),
      ),
      home: app.starting
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : app.user == null
          ? LoginPage(app)
          : DesktopShell(app, key: ValueKey(app.uid)),
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
    } catch (e) {
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
                    horizontal: wide ? 55 : 35,
                    vertical: 32,
                  ),
                  child: Center(child: AutofillGroup(child: form)),
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
      if (mounted)
        unawaited(
          offerStartupUpdate(
            context,
            application: widget.app,
          ).catchError((_) {}),
        );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refreshSystemProxy());
      unawaited(widget.app.checkin.automatic());
      unawaited(widget.app.clientConfig.refresh());
      unawaited(widget.app.patches.check());
      widget.app.notices.start();
    } else if ((!isAndroid && state == AppLifecycleState.inactive) ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.app.notices.pause();
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

  Widget mobile(BuildContext c) {
    final root = navigation.any((n) => n.$3 == route.kind) && history.isEmpty;
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
            Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Theme.of(c).dividerColor),
                ),
              ),
              child: Row(
                children: [
                  if (!root)
                    IconButton(
                      tooltip: '返回',
                      onPressed: back,
                      icon: const Icon(Icons.arrow_back_rounded),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(left: 6, right: 10),
                      child: Icon(Icons.auto_awesome_rounded, color: violet),
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
                  NoticeBell(
                    notices: widget.app.notices,
                    onPressed: () =>
                        open(const DeskRoute('noticeCenter', '消息提醒')),
                  ),
                ],
              ),
            ),
            Expanded(child: page()),
            if (root && MediaQuery.viewInsetsOf(c).bottom == 0)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(c).colorScheme.surface,
                  border: Border(
                    top: BorderSide(color: Theme.of(c).dividerColor),
                  ),
                ),
                child: Row(
                  children: [
                    for (final n in navigation)
                      Expanded(
                        child: Semantics(
                          selected: route.kind == n.$3,
                          button: true,
                          child: InkWell(
                            key: ValueKey('mobile.nav.${n.$3}'),
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
                                      color: route.kind == n.$3
                                          ? violet.withValues(alpha: .14)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      n.$1,
                                      size: 23,
                                      color: route.kind == n.$3
                                          ? violet
                                          : Theme.of(c)
                                                .colorScheme
                                                .onSurfaceVariant,
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
                                          ? violet
                                          : Theme.of(c)
                                                .colorScheme
                                                .onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
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
      'followPeople' => FollowPeoplePage(route, key: ValueKey(route.key)),
      'categories' => CategoryPage(key: ValueKey(route.key)),
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
                          'logs',
                        ].contains(route.kind)
                      ? 'mine'
                      : route.kind;
                  return Row(
                    children: [
                      Container(
                        width: full ? 222 : 86,
                        decoration: BoxDecoration(
                          color: Theme.of(c).colorScheme.surface,
                          border: Border(
                            right: BorderSide(color: Theme.of(c).dividerColor),
                          ),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                full ? 27 : 16,
                                short ? 18 : 35,
                                16,
                                short ? 20 : 40,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 31,
                                    color: violet,
                                  ),
                                  if (full) ...[
                                    const SizedBox(width: 14),
                                    const Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '星屿',
                                          style: TextStyle(
                                            fontSize: 25,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          'YOUR LITTLE UNIVERSE',
                                          style: TextStyle(
                                            fontSize: 7,
                                            letterSpacing: 1,
                                            color: violet,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (full)
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(29, 0, 0, 13),
                                  child: Text(
                                    '探索你的喜欢',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 10,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                              ),
                            for (final nav in [
                              (Icons.grid_view_rounded, '发现', 'home'),
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
                                  horizontal: full ? 17 : 12,
                                  vertical: 5,
                                ),
                                child: Tooltip(
                                  message: nav.$2,
                                  child: Material(
                                    color: selected == nav.$3
                                        ? violet.withValues(alpha: .12)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(14),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: () =>
                                          tab(DeskRoute(nav.$3, nav.$2)),
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: full ? 16 : 14,
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 30,
                                              height: 30,
                                              child: selected == nav.$3
                                                  ? IconBadge(nav.$1, size: 30)
                                                  : Icon(
                                                      nav.$1,
                                                      size: 22,
                                                      color: Theme.of(c)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                            ),
                                            if (full) ...[
                                              const SizedBox(width: 15),
                                              Text(
                                                nav.$2,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: selected == nav.$3
                                                      ? FontWeight.w700
                                                      : FontWeight.w500,
                                                  color: selected == nav.$3
                                                      ? violet
                                                      : null,
                                                ),
                                              ),
                                              const Spacer(),
                                              if (selected == nav.$3)
                                                const Icon(
                                                  Icons.circle,
                                                  size: 5,
                                                  color: violet,
                                                ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            const Spacer(),
                            if (full && !short)
                              Padding(
                                padding: const EdgeInsets.all(18),
                                child: Surface(
                                  padding: const EdgeInsets.all(15),
                                  color: violet.withValues(alpha: .065),
                                  child: const Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.nightlight_round,
                                        color: violet,
                                        size: 19,
                                      ),
                                      SizedBox(height: 10),
                                      Text(
                                        '留一点时间给热爱',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      SizedBox(height: 7),
                                      Text(
                                        '慢慢探索，自在阅读。',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: InkWell(
                                onTap: () =>
                                    tab(const DeskRoute('mine', '我的星屿')),
                                borderRadius: BorderRadius.circular(12),
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
                                              text(
                                                widget.app.user?['nickname'],
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            Text(
                                              'UID ${widget.app.uid}',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Icon(
                                        Icons.unfold_more,
                                        size: 16,
                                        color: Colors.grey,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
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
                              child: Row(
                                children: [
                                  if (history.isNotEmpty)
                                    IconButton(
                                      onPressed: back,
                                      tooltip: '返回 $backShortcutLabel',
                                      icon: const Icon(
                                        Icons.arrow_back,
                                        size: 20,
                                      ),
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
                                      constraints: const BoxConstraints(
                                        maxWidth: 490,
                                      ),
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
                                          prefixIcon: Icon(
                                            Icons.search_rounded,
                                            size: 20,
                                          ),
                                          suffixIcon: Padding(
                                            padding: EdgeInsets.only(top: 16),
                                            child: Text(
                                              '$primaryModifierLabel K',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ),
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
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
                                    onPressed: () => open(
                                      const DeskRoute('noticeCenter', '消息提醒'),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () =>
                                        widget.app.setDark(!widget.app.dark),
                                    tooltip: widget.app.dark ? '切换浅色' : '切换深色',
                                    icon: Icon(
                                      widget.app.dark
                                          ? Icons.light_mode_outlined
                                          : Icons.dark_mode_outlined,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () =>
                                        open(const DeskRoute('settings', '设置')),
                                    tooltip: '设置',
                                    icon: const Icon(
                                      Icons.settings_outlined,
                                      size: 21,
                                    ),
                                  ),
                                ],
                              ),
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
