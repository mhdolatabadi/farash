import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:farash/app/palette.dart';

/// Ambient illumination behind the semantic application surfaces.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final glass = FarashGlassColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: glass.backdrop,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.8, 0.1),
                    radius: 1,
                    colors: [glass.glow, glass.glow.withValues(alpha: 0)],
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

/// Blur is bounded to the few large panes, never every task row.
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
            offset: const Offset(0, 10),
            blurRadius: 28,
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
            ),
            // List tiles and ink inside paint on this transparent Material,
            // above the glass tint instead of under it.
            child: Material(
              type: MaterialType.transparency,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
