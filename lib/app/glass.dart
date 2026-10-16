import 'package:farash/app/atelier.dart';
import 'package:flutter/material.dart';

/// Compatibility hook for existing project navigation.
abstract final class GlassLamp {
  static final position = ValueNotifier<Alignment>(Alignment.center);
  static void placeFor(String key) {}
}

class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Theme.of(context).colorScheme.surface, child: child);
}

/// Legacy call sites now receive opaque atelier surfaces without blur.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 24,
    this.blur = 0,
    this.padding = EdgeInsets.zero,
    this.borderColor,
    this.shadow = false,
  });
  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final bool shadow;
  @override
  Widget build(BuildContext context) => AtelierPanel(
    radius: radius,
    borderColor: borderColor,
    padding: padding,
    lifted: shadow,
    child: child,
  );
}
