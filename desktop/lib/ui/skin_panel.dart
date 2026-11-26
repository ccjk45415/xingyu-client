import 'package:flutter/material.dart';

import '../core/skin.dart';
import '../core/state.dart';
import 'glass.dart';
import 'shared.dart';

/// Opens the skin & appearance switcher modal (Dialog on desktop, BottomSheet on mobile).
Future<void> showSkinPanel(
  BuildContext context,
  AppState app, {
  VoidCallback? onOpenMoreAppearance,
}) async {
  final compact = MediaQuery.sizeOf(context).width < 700;
  if (compact) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: AnimatedBuilder(
            animation: app,
            builder: (_, _) => _SkinPanelFrame(
              child: SkinPanelContent(
                app: app,
                compact: true,
                onClose: () => Navigator.pop(c),
                onOpenMoreAppearance: onOpenMoreAppearance == null
                    ? null
                    : () {
                        Navigator.pop(c);
                        onOpenMoreAppearance();
                      },
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .38),
    builder: (c) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: AnimatedBuilder(
          animation: app,
          builder: (_, _) => _SkinPanelFrame(
            child: SkinPanelContent(
              app: app,
              compact: false,
              onClose: () => Navigator.pop(c),
              onOpenMoreAppearance: onOpenMoreAppearance == null
                  ? null
                  : () {
                      Navigator.pop(c);
                      onOpenMoreAppearance();
                    },
            ),
          ),
        ),
      ),
    ),
  );
}

class _SkinPanelFrame extends StatelessWidget {
  final Widget child;
  const _SkinPanelFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    final skin = XingyuSkinTheme.of(context);
    if (skin.usesGlassChrome) {
      return GlassPanel(
        borderRadius: skin.isLiquid ? 32 : 28,
        blurSigma: skin.isLiquid ? 30 : 26,
        strong: true,
        padding: const EdgeInsets.all(24),
        child: child,
      );
    }
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 10,
      shadowColor: violet.withValues(alpha: .18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(
            alpha: .35,
          ),
        ),
      ),
      child: Padding(padding: const EdgeInsets.all(24), child: child),
    );
  }
}

class SkinPanelContent extends StatelessWidget {
  final AppState app;
  final bool compact;
  final VoidCallback? onClose;
  final VoidCallback? onOpenMoreAppearance;

  const SkinPanelContent({
    super.key,
    required this.app,
    this.compact = false,
    this.onClose,
    this.onOpenMoreAppearance,
  });

  @override
  Widget build(BuildContext context) {
    final skin = XingyuSkinTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(Icons.palette_outlined, size: 42),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '皮肤与外观',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '切换日夜光影与界面视觉风格，即刻生效',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onClose != null)
                IconButton(
                  tooltip: '关闭',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '色彩模式',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          _BrightnessSwitch(
            dark: app.dark,
            onChanged: (value) => app.setDark(value),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Text(
                '界面皮肤',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: skin.accentGradient),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  '毛玻璃 · 液态玻璃',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SkinSelectorGrid(app: app, compact: compact),
          if (onOpenMoreAppearance != null) ...[
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onOpenMoreAppearance,
                icon: const Icon(Icons.tune_rounded, size: 17),
                label: const Text('更多阅读与排版设置'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BrightnessSwitch extends StatelessWidget {
  final bool dark;
  final ValueChanged<bool> onChanged;
  const _BrightnessSwitch({required this.dark, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final skin = XingyuSkinTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final bg = skin.usesGlassChrome
        ? (skin.isDark
              ? Colors.white.withValues(alpha: .07)
              : Colors.white.withValues(alpha: .55))
        : scheme.surfaceContainerHighest.withValues(alpha: .55);

    Widget option({
      required Key key,
      required bool selected,
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          child: InkWell(
            key: key,
            onTap: onTap,
            borderRadius: BorderRadius.circular(skin.isLiquid ? 999 : 14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(skin.isLiquid ? 999 : 14),
                gradient: selected && skin.usesGlassChrome
                    ? LinearGradient(
                        colors: [
                          skin.accent.withValues(alpha: skin.isDark ? .34 : .18),
                          skin.accentSecondary.withValues(
                            alpha: skin.isDark ? .24 : .14,
                          ),
                        ],
                      )
                    : null,
                color: selected
                    ? (skin.usesGlassChrome
                          ? null
                          : scheme.primary.withValues(alpha: .14))
                    : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? scheme.primary.withValues(alpha: .55)
                      : Colors.transparent,
                  width: 1.1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: selected ? scheme.primary : scheme.onSurface,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(skin.isLiquid ? 999 : 18),
        border: Border.all(
          color: skin.usesGlassChrome
              ? skin.glassBorder
              : scheme.outlineVariant.withValues(alpha: .35),
        ),
      ),
      child: Row(
        children: [
          option(
            key: const Key('skin.mode.light'),
            selected: !dark,
            icon: Icons.light_mode_outlined,
            title: '浅色模式',
            subtitle: '明亮通透',
            onTap: () => onChanged(false),
          ),
          const SizedBox(width: 6),
          option(
            key: const Key('skin.mode.dark'),
            selected: dark,
            icon: Icons.dark_mode_outlined,
            title: '深色模式',
            subtitle: '沉浸护眼',
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

/// Reusable skin gallery grid (used in both the top-bar Skin Panel and Settings).
class SkinSelectorGrid extends StatelessWidget {
  final AppState app;
  final bool compact;
  const SkinSelectorGrid({super.key, required this.app, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final classicCard = _SkinPreviewCard(
      key: const Key('skin.option.classic'),
      skin: AppSkin.classic,
      darkPreview: app.dark,
      selected: app.skin == AppSkin.classic,
      badge: '经典轻量',
      compact: compact,
      onTap: () => app.setSkin(AppSkin.classic),
    );
    final glassCard = _SkinPreviewCard(
      key: const Key('skin.option.glass'),
      skin: AppSkin.glass,
      darkPreview: app.dark,
      selected: app.skin == AppSkin.glass,
      badge: '新毛玻璃',
      highlightBadge: true,
      compact: compact,
      onTap: () => app.setSkin(AppSkin.glass),
    );
    final liquidCard = _SkinPreviewCard(
      key: const Key('skin.option.liquid'),
      skin: AppSkin.liquid,
      darkPreview: app.dark,
      selected: app.skin == AppSkin.liquid,
      badge: '液态水镜',
      highlightBadge: true,
      compact: compact,
      onTap: () => app.setSkin(AppSkin.liquid),
    );

    if (compact) {
      return Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: classicCard),
              const SizedBox(width: 10),
              Expanded(child: glassCard),
            ],
          ),
          const SizedBox(height: 10),
          liquidCard,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: classicCard),
        const SizedBox(width: 12),
        Expanded(child: glassCard),
        const SizedBox(width: 12),
        Expanded(child: liquidCard),
      ],
    );
  }
}

class _SkinPreviewCard extends StatelessWidget {
  final AppSkin skin;
  final bool darkPreview;
  final bool selected;
  final String badge;
  final bool highlightBadge;
  final bool compact;
  final VoidCallback onTap;

  const _SkinPreviewCard({
    super.key,
    required this.skin,
    required this.darkPreview,
    required this.selected,
    required this.badge,
    this.highlightBadge = false,
    this.compact = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final currentTokens = XingyuSkinTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final previewTokens = XingyuSkinTheme.resolve(
      skin,
      darkPreview ? Brightness.dark : Brightness.light,
    );

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              currentTokens.isLiquid ? 24 : 20,
            ),
            color: currentTokens.usesGlassChrome
                ? (selected
                      ? currentTokens.accent.withValues(
                          alpha: currentTokens.isDark ? .18 : .10,
                        )
                      : (currentTokens.isDark
                            ? Colors.white.withValues(alpha: .05)
                            : Colors.white.withValues(alpha: .48)))
                : (selected
                      ? scheme.primary.withValues(alpha: .08)
                      : scheme.surfaceContainerLowest),
            border: Border.all(
              color: selected
                  ? scheme.primary
                  : (currentTokens.usesGlassChrome
                        ? currentTokens.glassBorder
                        : scheme.outlineVariant.withValues(alpha: .4)),
              width: selected ? 1.8 : 1.0,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: .18),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MiniSkinPreview(
                tokens: previewTokens,
                height: compact ? 82 : 112,
              ),
              SizedBox(height: compact ? 9 : 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      skin.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 13.5 : 15,
                        fontWeight: FontWeight.w800,
                        color: selected ? scheme.primary : scheme.onSurface,
                      ),
                    ),
                  ),
                  if (!compact)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: highlightBadge
                            ? LinearGradient(
                                colors: previewTokens.accentGradient,
                              )
                            : null,
                        color: highlightBadge
                            ? null
                            : scheme.primary.withValues(alpha: .12),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: highlightBadge ? Colors.white : scheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                skin.summary,
                maxLines: compact ? 2 : 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  height: 1.4,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (selected)
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 17,
                      color: scheme.primary,
                    )
                  else
                    Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: scheme.onSurfaceVariant.withValues(alpha: .55),
                          width: 1.5,
                        ),
                      ),
                    ),
                  const SizedBox(width: 6),
                  Text(
                    selected ? '当前使用中' : '点击切换',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniSkinPreview extends StatelessWidget {
  final XingyuSkinTheme tokens;
  final double height;
  const _MiniSkinPreview({required this.tokens, this.height = 112});

  @override
  Widget build(BuildContext context) {
    final glass = tokens.usesGlassChrome;
    final liquid = tokens.isLiquid;
    final dark = tokens.isDark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(liquid ? 18 : 14),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: tokens.backdropBase.length >= 2
                      ? tokens.backdropBase
                      : [tokens.backdropBase.first, tokens.backdropBase.first],
                ),
              ),
            ),
            if (glass && tokens.backdropOrbs.length >= 3) ...[
              Positioned(
                left: -18,
                top: -16,
                child: _OrbDot(color: tokens.backdropOrbs[0], size: 78),
              ),
              Positioned(
                right: -14,
                top: -10,
                child: _OrbDot(color: tokens.backdropOrbs[1], size: 70),
              ),
              Positioned(
                right: 26,
                bottom: -24,
                child: _OrbDot(color: tokens.backdropOrbs[2], size: 74),
              ),
            ],
            if (liquid)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: dark ? .22 : .55),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.all(glass ? 8 : 0),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(glass ? 10 : 0),
                      color: glass
                          ? tokens.glassFillTop
                          : (dark ? const Color(0xff252232) : Colors.white),
                      border: Border.all(
                        color: glass
                            ? tokens.glassBorder
                            : Colors.black.withValues(alpha: .06),
                        width: .8,
                      ),
                    ),
                    padding: const EdgeInsets.all(5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: tokens.accentGradient,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 6,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            gradient: glass
                                ? LinearGradient(colors: tokens.accentGradient)
                                : null,
                            color: glass
                                ? null
                                : tokens.accent.withValues(alpha: .28),
                          ),
                        ),
                        const SizedBox(height: 5),
                        for (var i = 0; i < 2; i++) ...[
                          Container(
                            height: 4,
                            width: i == 1 ? 20 : 26,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(2),
                              color: (dark ? Colors.white : Colors.black)
                                  .withValues(alpha: .16),
                            ),
                          ),
                          if (i == 0) const SizedBox(height: 4),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: glass ? 7 : 1),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.all(glass ? 0 : 8),
                      child: Column(
                        children: [
                          Container(
                            height: 20,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                glass ? 9 : 6,
                              ),
                              color: glass
                                  ? tokens.glassFillTop
                                  : (dark
                                        ? const Color(0xff252232)
                                        : Colors.white),
                              border: Border.all(
                                color: glass
                                    ? tokens.glassBorder
                                    : Colors.black.withValues(alpha: .06),
                                width: .8,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 48,
                                      ),
                                      child: Container(
                                        height: 6,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                          color:
                                              (dark
                                                      ? Colors.white
                                                      : Colors.black)
                                                  .withValues(alpha: .14),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: tokens.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 7),
                          Expanded(
                            child: Row(
                              children: [
                                for (var i = 0; i < 2; i++) ...[
                                  if (i > 0) const SizedBox(width: 7),
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          glass ? 11 : 8,
                                        ),
                                        color: glass
                                            ? tokens.glassFillTop
                                            : (dark
                                                  ? const Color(0xff252232)
                                                  : Colors.white),
                                        border: Border.all(
                                          color: glass
                                              ? tokens.glassBorder
                                              : Colors.black.withValues(
                                                  alpha: .06,
                                                ),
                                          width: .8,
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(6),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                gradient: LinearGradient(
                                                  colors: [
                                                    tokens.accent.withValues(
                                                      alpha: .32,
                                                    ),
                                                    tokens.accentSecondary
                                                        .withValues(alpha: .28),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Container(
                                            height: 5,
                                            width: 46,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                              color:
                                                  (dark
                                                          ? Colors.white
                                                          : Colors.black)
                                                      .withValues(alpha: .24),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
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
          ],
        ),
      ),
    );
  }
}

class _OrbDot extends StatelessWidget {
  final Color color;
  final double size;
  const _OrbDot({required this.color, required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [color, color.withValues(alpha: 0)],
      ),
    ),
  );
}
