import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:farash/app/motion.dart';
import 'package:farash/app/palette.dart';

/// Where the room's lamp stands behind the glass. Choosing another project
/// moves it, so the light itself shows that the place changed.
abstract final class GlassLamp {
  static final position = ValueNotifier<Alignment>(const Alignment(0.55, -0.7));

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

/// The night outside and the lamp behind the glass.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final glass = FarashGlassColors.of(context);
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
                      gradient: RadialGradient(
                        center: at,
                        radius: 0.75,
                        colors: [
                          glass.glow,
                          glass.glow.withValues(alpha: glass.glow.a * 0.35),
                          glass.glow.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.38, 1],
                      ),
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

/// A pane of the pressed, patterned glass. Blur is bounded to the few large
/// panes, never every task row.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 24,
    this.blur = 16,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final glass = FarashGlassColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: glass.shadow,
            offset: const Offset(0, 12),
            blurRadius: 32,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              color: glass.pane,
              border: Border.all(color: glass.paneBorder),
              // The lit edge where lamplight catches the top of the pane.
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: const Alignment(0, -0.6),
                colors: [glass.relief, glass.relief.withValues(alpha: 0)],
              ),
            ),
            child: CustomPaint(
              isComplex: true,
              painter: _PebbleRelief(glass.relief, glass.reliefShade),
              // Its own layer, so scrolling the list never repaints the
              // pattern. List tiles and ink paint on this transparent
              // Material, above the glass tint instead of under it.
              child: RepaintBoundary(
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

/// The pressed-pebble pattern of Iranian privacy glass: rows of small
/// domes, each lit on one side and shaded on the other. Drawn once per pane
/// and kept faint so text stays crisp over it.
class _PebbleRelief extends CustomPainter {
  _PebbleRelief(this.lit, this.shade);

  final Color lit;
  final Color shade;
  static const _step = 13.0;

  @override
  void paint(Canvas canvas, Size size) {
    final light = Paint()..color = lit;
    final dark = Paint()..color = shade;
    var row = 0;
    for (var y = _step / 2; y < size.height; y += _step * 0.87, row++) {
      final shift = row.isOdd ? _step / 2 : 0.0;
      for (var x = shift; x < size.width; x += _step) {
        canvas.drawCircle(Offset(x - 0.8, y - 0.8), 1.6, light);
        canvas.drawCircle(Offset(x + 0.9, y + 0.9), 1.6, dark);
      }
    }
  }

  @override
  bool shouldRepaint(_PebbleRelief old) => old.lit != lit || old.shade != shade;
}
