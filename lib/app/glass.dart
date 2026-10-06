import 'dart:ui';
import 'package:flutter/material.dart';

/// Ambient illumination behind the semantic application surfaces.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: dark
              ? const [Color(0xFF193B40), Color(0xFF101E25), Color(0xFF23343B)]
              : const [Color(0xFFD7EEEB), Color(0xFFF5F8F3), Color(0xFFDAE9ED)],
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
                    colors: [
                      (dark ? const Color(0xFF53847C) : Colors.white)
                          .withValues(alpha: dark ? 0.18 : 0.7),
                      Colors.transparent,
                    ],
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: (dark ? Colors.black : const Color(0xFF33565C)).withValues(
              alpha: dark ? 0.16 : 0.07,
            ),
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
              color: (dark ? const Color(0xFF1B3037) : Colors.white).withValues(
                alpha: dark ? 0.9 : 0.78,
              ),
              border: Border.all(
                color: (dark ? const Color(0xFF92BAB8) : Colors.white)
                    .withValues(alpha: dark ? 0.22 : 0.88),
              ),
            ),
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
