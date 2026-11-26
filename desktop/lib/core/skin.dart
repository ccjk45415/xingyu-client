import 'package:flutter/material.dart';

import '../ui/shared.dart';

enum AppSkin {
  classic('classic', '星屿经典', '清爽纯色卡片与柔和紫粉配色'),
  glass('glass', '琉璃毛玻璃', '弥散极光背景、悬浮磨砂玻璃与微光折边'),
  liquid('liquid', '液态玻璃', '高透水镜折射、流体光波与全圆角液态胶囊');

  final String id;
  final String label;
  final String summary;
  const AppSkin(this.id, this.label, this.summary);

  static AppSkin parse(Object? raw) {
    final value = raw is String ? raw.trim().toLowerCase() : '';
    for (final skin in AppSkin.values) {
      if (skin.id == value) return skin;
    }
    return AppSkin.classic;
  }
}

@immutable
class XingyuSkinTheme extends ThemeExtension<XingyuSkinTheme> {
  final AppSkin skin;
  final Brightness brightness;
  final List<Color> backdropBase;
  final List<Color> backdropOrbs;
  final Color glassFillTop;
  final Color glassFillBottom;
  final Color glassFillStrong;
  final Color glassBorder;
  final Color glassHighlight;
  final Color specularBottom;
  final Color glassShadow;
  final Color accent;
  final Color accentSecondary;
  final List<Color> accentGradient;
  final double panelRadius;
  final double cardRadius;
  final double blurSigma;

  const XingyuSkinTheme({
    required this.skin,
    required this.brightness,
    required this.backdropBase,
    required this.backdropOrbs,
    required this.glassFillTop,
    required this.glassFillBottom,
    required this.glassFillStrong,
    required this.glassBorder,
    required this.glassHighlight,
    required this.specularBottom,
    required this.glassShadow,
    required this.accent,
    required this.accentSecondary,
    required this.accentGradient,
    required this.panelRadius,
    required this.cardRadius,
    required this.blurSigma,
  });

  bool get isGlass => skin == AppSkin.glass;
  bool get isLiquid => skin == AppSkin.liquid;
  bool get usesGlassChrome => isGlass || isLiquid;
  bool get isDark => brightness == Brightness.dark;

  static XingyuSkinTheme of(BuildContext context) =>
      Theme.of(context).extension<XingyuSkinTheme>() ??
      XingyuSkinTheme.resolve(AppSkin.classic, Theme.of(context).brightness);

  static XingyuSkinTheme resolve(AppSkin skin, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    if (skin == AppSkin.liquid) {
      if (dark) {
        return const XingyuSkinTheme(
          skin: AppSkin.liquid,
          brightness: Brightness.dark,
          backdropBase: [
            Color(0xff040a16),
            Color(0xff081428),
            Color(0xff061b29),
          ],
          backdropOrbs: [
            Color(0x6622d3ee),
            Color(0x522563eb),
            Color(0x4710b981),
          ],
          glassFillTop: Color(0x7a182e4c),
          glassFillBottom: Color(0x590a162a),
          glassFillStrong: Color(0xad12233d),
          glassBorder: Color(0x47bfefff),
          glassHighlight: Color(0x80ffffff),
          specularBottom: Color(0x4d38bdf8),
          glassShadow: Color(0x73020612),
          accent: Color(0xff38bdf8),
          accentSecondary: Color(0xff2dd4bf),
          accentGradient: [
            Color(0xff38bdf8),
            Color(0xff22d3ee),
            Color(0xff2dd4bf),
          ],
          panelRadius: 30,
          cardRadius: 26,
          blurSigma: 28,
        );
      }
      return const XingyuSkinTheme(
        skin: AppSkin.liquid,
        brightness: Brightness.light,
        backdropBase: [
          Color(0xffe2f2ff),
          Color(0xffedf9ff),
          Color(0xfff5fbff),
        ],
        backdropOrbs: [
          Color(0x6638bdf8),
          Color(0x4d3b82f6),
          Color(0x522dd4bf),
        ],
        glassFillTop: Color(0x99ffffff),
        glassFillBottom: Color(0x5ee8f7ff),
        glassFillStrong: Color(0xccffffff),
        glassBorder: Color(0xebffffff),
        glassHighlight: Color(0xffffffff),
        specularBottom: Color(0x6638bdf8),
        glassShadow: Color(0x240284c7),
        accent: Color(0xff0284c7),
        accentSecondary: Color(0xff06b6d4),
        accentGradient: [
          Color(0xff0284c7),
          Color(0xff0ea5e9),
          Color(0xff14b8a6),
        ],
        panelRadius: 30,
        cardRadius: 26,
        blurSigma: 26,
      );
    }
    if (skin == AppSkin.glass) {
      if (dark) {
        return const XingyuSkinTheme(
          skin: AppSkin.glass,
          brightness: Brightness.dark,
          backdropBase: [
            Color(0xff0b0e1c),
            Color(0xff12152b),
            Color(0xff17132c),
          ],
          backdropOrbs: [
            Color(0x526366f1),
            Color(0x3322d3ee),
            Color(0x38ec4899),
          ],
          glassFillTop: Color(0xa6232846),
          glassFillBottom: Color(0x80181b32),
          glassFillStrong: Color(0xc7202542),
          glassBorder: Color(0x2effffff),
          glassHighlight: Color(0x47ffffff),
          specularBottom: Color(0x00000000),
          glassShadow: Color(0x66040610),
          accent: Color(0xffa78bfa),
          accentSecondary: Color(0xff38bdf8),
          accentGradient: [
            Color(0xff818cf8),
            Color(0xffa855f7),
            Color(0xffec4899),
          ],
          panelRadius: 24,
          cardRadius: 22,
          blurSigma: 22,
        );
      }
      return const XingyuSkinTheme(
        skin: AppSkin.glass,
        brightness: Brightness.light,
        backdropBase: [
          Color(0xffeef3ff),
          Color(0xfff4efff),
          Color(0xfffff2f9),
        ],
        backdropOrbs: [
          Color(0x527dd3fc),
          Color(0x47a78bfa),
          Color(0x42f472b6),
        ],
        glassFillTop: Color(0xc7ffffff),
        glassFillBottom: Color(0x8fffffff),
        glassFillStrong: Color(0xd9ffffff),
        glassBorder: Color(0xd9ffffff),
        glassHighlight: Color(0xf5ffffff),
        specularBottom: Color(0x00000000),
        glassShadow: Color(0x1f6366f1),
        accent: Color(0xff6366f1),
        accentSecondary: Color(0xffec4899),
        accentGradient: [
          Color(0xff6366f1),
          Color(0xff8b5cf6),
          Color(0xffec4899),
        ],
        panelRadius: 24,
        cardRadius: 22,
        blurSigma: 20,
      );
    }
    return XingyuSkinTheme(
      skin: AppSkin.classic,
      brightness: brightness,
      backdropBase: dark
          ? const [Color(0xff1b1926), Color(0xff1b1926)]
          : const [Color(0xfff8f7fc), Color(0xfff8f7fc)],
      backdropOrbs: const [],
      glassFillTop: dark ? const Color(0xff252232) : Colors.white,
      glassFillBottom: dark ? const Color(0xff252232) : Colors.white,
      glassFillStrong: dark ? const Color(0xff252232) : Colors.white,
      glassBorder: dark
          ? const Color(0x33ffffff)
          : const Color(0x1f8a6adb),
      glassHighlight: Colors.transparent,
      specularBottom: Colors.transparent,
      glassShadow: violet.withValues(alpha: .09),
      accent: violet,
      accentSecondary: pink,
      accentGradient: const [violet, pink],
      panelRadius: 20,
      cardRadius: 20,
      blurSigma: 0,
    );
  }

  @override
  XingyuSkinTheme copyWith({
    AppSkin? skin,
    Brightness? brightness,
    List<Color>? backdropBase,
    List<Color>? backdropOrbs,
    Color? glassFillTop,
    Color? glassFillBottom,
    Color? glassFillStrong,
    Color? glassBorder,
    Color? glassHighlight,
    Color? specularBottom,
    Color? glassShadow,
    Color? accent,
    Color? accentSecondary,
    List<Color>? accentGradient,
    double? panelRadius,
    double? cardRadius,
    double? blurSigma,
  }) => XingyuSkinTheme(
    skin: skin ?? this.skin,
    brightness: brightness ?? this.brightness,
    backdropBase: backdropBase ?? this.backdropBase,
    backdropOrbs: backdropOrbs ?? this.backdropOrbs,
    glassFillTop: glassFillTop ?? this.glassFillTop,
    glassFillBottom: glassFillBottom ?? this.glassFillBottom,
    glassFillStrong: glassFillStrong ?? this.glassFillStrong,
    glassBorder: glassBorder ?? this.glassBorder,
    glassHighlight: glassHighlight ?? this.glassHighlight,
    specularBottom: specularBottom ?? this.specularBottom,
    glassShadow: glassShadow ?? this.glassShadow,
    accent: accent ?? this.accent,
    accentSecondary: accentSecondary ?? this.accentSecondary,
    accentGradient: accentGradient ?? this.accentGradient,
    panelRadius: panelRadius ?? this.panelRadius,
    cardRadius: cardRadius ?? this.cardRadius,
    blurSigma: blurSigma ?? this.blurSigma,
  );

  @override
  XingyuSkinTheme lerp(ThemeExtension<XingyuSkinTheme>? other, double t) {
    if (other is! XingyuSkinTheme) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? b;
    List<Color> mixList(List<Color> a, List<Color> b) {
      if (a.isEmpty) return b;
      if (b.isEmpty) return a;
      final len = a.length > b.length ? a.length : b.length;
      return [
        for (var i = 0; i < len; i++)
          mix(a[i % a.length], b[i % b.length]),
      ];
    }

    return XingyuSkinTheme(
      skin: t < 0.5 ? skin : other.skin,
      brightness: t < 0.5 ? brightness : other.brightness,
      backdropBase: mixList(backdropBase, other.backdropBase),
      backdropOrbs: t < 0.5 ? backdropOrbs : other.backdropOrbs,
      glassFillTop: mix(glassFillTop, other.glassFillTop),
      glassFillBottom: mix(glassFillBottom, other.glassFillBottom),
      glassFillStrong: mix(glassFillStrong, other.glassFillStrong),
      glassBorder: mix(glassBorder, other.glassBorder),
      glassHighlight: mix(glassHighlight, other.glassHighlight),
      specularBottom: mix(specularBottom, other.specularBottom),
      glassShadow: mix(glassShadow, other.glassShadow),
      accent: mix(accent, other.accent),
      accentSecondary: mix(accentSecondary, other.accentSecondary),
      accentGradient: mixList(accentGradient, other.accentGradient),
      panelRadius: panelRadius + (other.panelRadius - panelRadius) * t,
      cardRadius: cardRadius + (other.cardRadius - cardRadius) * t,
      blurSigma: blurSigma + (other.blurSigma - blurSigma) * t,
    );
  }
}

ThemeData buildXingyuTheme(
  AppSkin skin,
  Brightness brightness, {
  required String? fontFamily,
}) {
  final dark = brightness == Brightness.dark;
  final tokens = XingyuSkinTheme.resolve(skin, brightness);
  final glass = tokens.usesGlassChrome;
  final liquid = tokens.isLiquid;
  final primaryColor = glass ? tokens.accent : violet;
  final secondaryColor = glass ? tokens.accentSecondary : pink;
  final surfaceColor = liquid
      ? (dark ? const Color(0xd10e1e36) : const Color(0xd9ffffff))
      : glass
      ? (dark ? const Color(0xd91d223c) : const Color(0xe0ffffff))
      : (dark ? const Color(0xff252232) : Colors.white);
  final onSurfaceColor = liquid
      ? (dark ? const Color(0xfff0f9ff) : const Color(0xff0f172a))
      : glass
      ? (dark ? const Color(0xfff4f3ff) : const Color(0xff1e1b3a))
      : (dark ? const Color(0xffeee8fb) : ink);
  final onSurfaceVariantColor = liquid
      ? (dark ? const Color(0xffa6c4de) : const Color(0xff3e556e))
      : glass
      ? (dark ? const Color(0xffb5b4d4) : const Color(0xff524e6e))
      : null;

  final baseScheme = ColorScheme.fromSeed(
    seedColor: primaryColor,
    brightness: brightness,
  );
  final scheme = baseScheme.copyWith(
    primary: primaryColor,
    secondary: secondaryColor,
    surface: surfaceColor,
    onSurface: onSurfaceColor,
    onSurfaceVariant: onSurfaceVariantColor ?? baseScheme.onSurfaceVariant,
    outlineVariant: liquid
        ? (dark ? const Color(0x4dbfefff) : const Color(0x520284c7))
        : glass
        ? (dark ? const Color(0x40ffffff) : const Color(0x476366f1))
        : baseScheme.outlineVariant,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: [tokens],
    fontFamily: fontFamily,
    fontFamilyFallback: const ['Segoe UI', 'Microsoft YaHei'],
    scaffoldBackgroundColor: glass
        ? Colors.transparent
        : (dark ? const Color(0xff1b1926) : const Color(0xfff8f7fc)),
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
        color: liquid
            ? (dark ? const Color(0xeb102542) : const Color(0xeb0f172a))
            : glass
            ? (dark ? const Color(0xeb262b4d) : const Color(0xeb1e1b3a))
            : (dark ? const Color(0xffeee7fc) : const Color(0xff3e3458)),
        borderRadius: BorderRadius.circular(liquid ? 14 : 11),
        border: glass
            ? Border.all(
                color: liquid
                    ? tokens.glassBorder
                    : Colors.white.withValues(alpha: .16),
              )
            : null,
      ),
      textStyle: TextStyle(
        color: glass ? Colors.white : (dark ? ink : Colors.white),
        fontSize: 12,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(42, 42),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(liquid ? 999 : (glass ? 14 : 13)),
        ),
        foregroundColor: scheme.onSurfaceVariant,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 42),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(liquid ? 999 : (glass ? 14 : 12)),
        ),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontFamilyFallback: const ['Segoe UI', 'Microsoft YaHei'],
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: liquid
          ? (dark ? const Color(0xe60c1d35) : const Color(0xebffffff))
          : glass
          ? (dark ? const Color(0xeb1b203a) : const Color(0xf0ffffff))
          : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(liquid ? 32 : (glass ? 28 : 24)),
        side: glass
            ? BorderSide(color: tokens.glassBorder, width: liquid ? 1.2 : 1.1)
            : BorderSide.none,
      ),
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: liquid
          ? (dark ? const Color(0xe60a192e) : const Color(0xebffffff))
          : glass
          ? (dark ? const Color(0xeb191d36) : const Color(0xf0ffffff))
          : scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(liquid ? 32 : 28),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: glass ? tokens.glassFillTop : scheme.surface,
      elevation: glass ? 0 : 1,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        side: BorderSide(
          color: glass
              ? tokens.glassBorder
              : scheme.outlineVariant.withValues(alpha: .3),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: liquid
          ? (dark ? const Color(0x66173152) : const Color(0xa6ffffff))
          : glass
          ? (dark ? const Color(0x80262b4b) : const Color(0xb3ffffff))
          : (dark ? const Color(0xff302b40) : const Color(0xfff5f2fb)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(liquid ? 999 : (glass ? 16 : 14)),
        borderSide: glass
            ? BorderSide(color: tokens.glassBorder)
            : BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(liquid ? 999 : (glass ? 16 : 14)),
        borderSide: glass
            ? BorderSide(color: tokens.glassBorder)
            : BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(liquid ? 999 : (glass ? 16 : 14)),
        borderSide: glass
            ? BorderSide(
                color: primaryColor.withValues(alpha: .78),
                width: 1.5,
              )
            : BorderSide(color: primaryColor.withValues(alpha: .45)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(liquid ? 999 : (glass ? 15 : 13)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        side: glass ? BorderSide(color: tokens.glassBorder) : null,
        backgroundColor: liquid
            ? (dark ? const Color(0x40162f50) : const Color(0x73ffffff))
            : glass
            ? (dark ? const Color(0x40262b4b) : const Color(0x80ffffff))
            : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(liquid ? 999 : (glass ? 15 : 13)),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      side: glass ? BorderSide(color: tokens.glassBorder) : BorderSide.none,
      backgroundColor: liquid
          ? (dark ? const Color(0x52173152) : const Color(0x99ffffff))
          : glass
          ? (dark ? const Color(0x66252a48) : const Color(0xa6ffffff))
          : null,
      selectedColor: glass
          ? primaryColor.withValues(alpha: dark ? .30 : .18)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(liquid ? 999 : (glass ? 13 : 11)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(primaryColor.withValues(alpha: .45)),
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(7),
    ),
    dividerColor: liquid
        ? (dark ? const Color(0x2ebfefff) : const Color(0x260284c7))
        : glass
        ? (dark ? const Color(0x26ffffff) : const Color(0x246366f1))
        : scheme.outlineVariant.withValues(alpha: .35),
  );
}
