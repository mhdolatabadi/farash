import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:farash/app/motion.dart';
import 'package:farash/app/palette.dart';

/// Where the room's lamp stands behind the glass. Choosing another project
/// moves it, so the light itself shows that the place changed.
abstract final class GlassLamp {
  static final position = ValueNotifier<Alignment>(const Alignment(0.9, -0.9));

  /// A stable spot for [key] (a project id), kept in the upper half where
  /// the light falls behind the heading and the list.
  static void placeFor(String key) {
    final hash = key.codeUnits.fold<int>(17, (h, c) => (h * 31 + c) & 0xffff);
    position.value = Alignment(
      -0.7 + (hash % 140) / 100,
      -0.85 + ((hash ~/ 140) % 50) / 100,
    );
  }
}

/// The room behind the glass: a soft gradient lit by three lights, a
/// peach lamp that moves with the project, lavender across the room and
/// mint near the floor. Panes frost this light, so the glass reads as glass.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final glass = FarashGlassColors.of(context);
    RadialGradient bloom(Alignment at, Color color, double radius) =>
        RadialGradient(
          center: at,
          radius: radius,
          colors: [
            color,
            color.withValues(alpha: color.a * 0.4),
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: glass.backdrop,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final (at, color, radius) in [
            (const Alignment(-1, -0.1), glass.light, 0.95),
            (const Alignment(0.4, 1.05), glass.mist, 0.85),
          ])
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: bloom(at, color, radius)),
                ),
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder(
                valueListenable: GlassLamp.position,
                builder: (context, lamp, _) => TweenAnimationBuilder(
                  tween: AlignmentTween(end: lamp),
                  duration: Motion.of(
                    context,
                    const Duration(milliseconds: 900),
                  ),
                  curve: Curves.easeInOutCubic,
                  builder: (context, at, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: bloom(at, glass.glow, 0.9),
                    ),
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// A pane of frosted glass, for the few surfaces content passes beneath:
/// the navigation pane, the capture bar, the editor beside the list and
/// the app bar once the list scrolls under it. Never nest one in another.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 24,
    this.blur = 20,
    this.padding = EdgeInsets.zero,
    this.borderColor,
    this.shadow = true,
  });
  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry padding;

  /// Replaces the glass edge, as a focused capture bar does.
  final Color? borderColor;

  /// Floating panes cast a shadow; panes flush with an edge do not.
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final glass = FarashGlassColors.of(context);
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          if (shadow)
            BoxShadow(
              color: glass.shadow,
              offset: const Offset(0, 8),
              blurRadius: 24,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(color: glass.pane),
            // The lit top edge, where the light catches the pane.
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: const Alignment(0, -0.55),
                  colors: [glass.edge, glass.edge.withValues(alpha: 0)],
                ),
              ),
              position: DecorationPosition.background,
              child: AnimatedContainer(
                duration: Motion.of(context, Motion.quick),
                decoration: BoxDecoration(
                  borderRadius: shape,
                  border: Border.all(
                    color: borderColor ?? glass.paneBorder,
                    width: borderColor == null ? 1 : 1.5,
                  ),
                ),
                // List tiles and ink paint on this transparent Material,
                // above the glass tint instead of under it.
                child: Material(
                  type: MaterialType.transparency,
                  child: Padding(padding: padding, child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
