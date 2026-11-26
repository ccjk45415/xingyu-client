import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/skin.dart';

/// Ambient aurora / liquid-wave backdrop rendered behind transparent scaffolds.
class GlassBackdrop extends StatelessWidget {
  final Widget child;
  const GlassBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final skin = XingyuSkinTheme.of(context);
    if (!skin.usesGlassChrome) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: skin.isLiquid
                ? _LiquidWaveBackdropPainter(
                    baseColors: skin.backdropBase,
                    waveColors: skin.backdropOrbs,
                    dark: skin.isDark,
                  )
                : _AuroraBackdropPainter(
                    baseColors: skin.backdropBase,
                    orbColors: skin.backdropOrbs,
                    dark: skin.isDark,
                  ),
          ),
        ),
        child,
      ],
    );
  }
}

class _AuroraBackdropPainter extends CustomPainter {
  final List<Color> baseColors;
  final List<Color> orbColors;
  final bool dark;

  const _AuroraBackdropPainter({
    required this.baseColors,
    required this.orbColors,
    required this.dark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: baseColors.length >= 2
            ? baseColors
            : [const Color(0xffeef3ff), const Color(0xfffff2f9)],
      ).createShader(rect);
    canvas.drawRect(rect, basePaint);

    if (orbColors.isEmpty) return;

    final maxSide = size.longestSide;
    final orbs = [
      (
        center: Offset(size.width * .12, size.height * .14),
        radius: maxSide * .46,
        color: orbColors[0],
      ),
      (
        center: Offset(size.width * .86, size.height * .20),
        radius: maxSide * .42,
        color: orbColors[orbColors.length > 1 ? 1 : 0],
      ),
      (
        center: Offset(size.width * .56, size.height * .88),
        radius: maxSide * .48,
        color: orbColors[orbColors.length > 2 ? 2 : 0],
      ),
    ];

    for (final orb in orbs) {
      final orbRect = Rect.fromCircle(center: orb.center, radius: orb.radius);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            orb.color,
            orb.color.withValues(alpha: orb.color.a * .35),
            orb.color.withValues(alpha: 0),
          ],
          stops: const [0, .48, 1],
        ).createShader(orbRect);
      canvas.drawCircle(orb.center, orb.radius, paint);
    }

    canvas.drawRect(
      rect,
      Paint()
        ..color = (dark ? const Color(0xff0b0e1c) : Colors.white)
            .withValues(alpha: dark ? .18 : .14),
    );
  }

  @override
  bool shouldRepaint(covariant _AuroraBackdropPainter oldDelegate) =>
      oldDelegate.dark != dark ||
      oldDelegate.baseColors != baseColors ||
      oldDelegate.orbColors != orbColors;
}

class _LiquidWaveBackdropPainter extends CustomPainter {
  final List<Color> baseColors;
  final List<Color> waveColors;
  final bool dark;

  const _LiquidWaveBackdropPainter({
    required this.baseColors,
    required this.waveColors,
    required this.dark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: baseColors.length >= 2
              ? baseColors
              : [const Color(0xffe2f2ff), const Color(0xfff5fbff)],
        ).createShader(rect),
    );

    if (waveColors.isEmpty) return;

    final c0 = waveColors[0];
    final c1 = waveColors[waveColors.length > 1 ? 1 : 0];
    final c2 = waveColors[waveColors.length > 2 ? 2 : 0];

    // Upper sweeping liquid ribbon
    final upperWave = Path()
      ..moveTo(0, size.height * .26)
      ..cubicTo(
        size.width * .28,
        size.height * .04,
        size.width * .62,
        size.height * .42,
        size.width,
        size.height * .16,
      )
      ..lineTo(size.width, 0)
      ..lineTo(0, 0)
      ..close();
    canvas.drawPath(
      upperWave,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            c0.withValues(alpha: dark ? .36 : .34),
            c1.withValues(alpha: dark ? .26 : .22),
            c2.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );

    // Lower flowing caustic wave
    final lowerWave = Path()
      ..moveTo(0, size.height * .78)
      ..cubicTo(
        size.width * .34,
        size.height * .58,
        size.width * .68,
        size.height * .96,
        size.width,
        size.height * .68,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      lowerWave,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [
            c2.withValues(alpha: dark ? .30 : .28),
            c0.withValues(alpha: dark ? .22 : .20),
            c1.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );

    // Specular water-lens caustic highlights
    final maxSide = size.longestSide;
    final lenses = [
      (Offset(size.width * .18, size.height * .22), maxSide * .34, c0),
      (Offset(size.width * .84, size.height * .32), maxSide * .30, c1),
      (Offset(size.width * .48, size.height * .82), maxSide * .36, c2),
    ];
    for (final lens in lenses) {
      canvas.drawCircle(
        lens.$1,
        lens.$2,
        Paint()
          ..shader = RadialGradient(
            colors: [
              lens.$3.withValues(alpha: dark ? .32 : .28),
              lens.$3.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: lens.$1, radius: lens.$2)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LiquidWaveBackdropPainter oldDelegate) =>
      oldDelegate.dark != dark ||
      oldDelegate.baseColors != baseColors ||
      oldDelegate.waveColors != waveColors;
}

/// True frosted / liquid-glass panel using BackdropFilter + optical specular highlights.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;
  final double? blurSigma;
  final Color? tintTop;
  final Color? tintBottom;
  final bool strong;
  final bool elevated;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.blurSigma,
    this.tintTop,
    this.tintBottom,
    this.strong = false,
    this.elevated = true,
  });

  @override
  Widget build(BuildContext context) {
    final skin = XingyuSkinTheme.of(context);
    final radius = borderRadius ?? skin.panelRadius;
    final sigma = blurSigma ?? skin.blurSigma;
    final topColor =
        tintTop ?? (strong ? skin.glassFillStrong : skin.glassFillTop);
    final bottomColor =
        tintBottom ?? (strong ? skin.glassFillTop : skin.glassFillBottom);
    final liquid = skin.isLiquid;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: skin.glassShadow,
                  blurRadius: liquid ? 34 : (skin.isDark ? 30 : 24),
                  offset: Offset(0, liquid ? 12 : 10),
                  spreadRadius: -4,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [topColor, bottomColor],
              ),
              border: Border.all(
                color: skin.glassBorder,
                width: liquid ? 1.25 : 1.05,
              ),
            ),
            child: Stack(
              children: [
                if (liquid)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: 22,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(
                                alpha: skin.isDark ? .16 : .48,
                              ),
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (skin.usesGlassChrome)
                  Positioned(
                    left: radius * .55,
                    right: radius * .55,
                    top: 0,
                    height: liquid ? 1.6 : 1.2,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              skin.glassHighlight.withValues(alpha: 0),
                              skin.glassHighlight,
                              skin.glassHighlight.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (liquid)
                  Positioned(
                    left: radius * .65,
                    right: radius * .65,
                    bottom: 0,
                    height: 1.4,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              skin.specularBottom.withValues(alpha: 0),
                              skin.specularBottom,
                              skin.specularBottom.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (padding != null)
                  Padding(padding: padding!, child: child)
                else
                  child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lightweight frosted / liquid-glass surface for repeated cards.
class GlassSurfaceBox extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;
  final Color? color;
  final bool highlighted;

  const GlassSurfaceBox({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.color,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final skin = XingyuSkinTheme.of(context);
    final radius = borderRadius ?? skin.cardRadius;
    final liquid = skin.isLiquid;
    final topColor = color ?? skin.glassFillTop;
    final bottomColor = color != null
        ? color!.withValues(alpha: (color!.a * .82).clamp(0.0, 1.0))
        : skin.glassFillBottom;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [topColor, bottomColor],
        ),
        border: Border.all(
          color: highlighted
              ? skin.accent.withValues(alpha: skin.isDark ? .68 : .58)
              : skin.glassBorder,
          width: highlighted ? 1.35 : (liquid ? 1.15 : 1.0),
        ),
        boxShadow: [
          BoxShadow(
            color: highlighted
                ? skin.accent.withValues(alpha: skin.isDark ? .26 : .18)
                : skin.glassShadow,
            blurRadius: highlighted ? 28 : (liquid ? 22 : 18),
            offset: const Offset(0, 8),
            spreadRadius: -4,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            if (liquid)
              Positioned(
                left: radius * .5,
                right: radius * .5,
                top: 0,
                height: 1.4,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          skin.glassHighlight.withValues(alpha: 0),
                          skin.glassHighlight.withValues(alpha: .85),
                          skin.glassHighlight.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (padding != null)
              Padding(padding: padding!, child: child)
            else
              child,
          ],
        ),
      ),
    );
  }
}
