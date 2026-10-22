import 'package:flutter/material.dart';

/// The app's mark: a check in a rounded square of the primary color.
class FarashMark extends StatelessWidget {
  const FarashMark({super.key, this.size = 28});
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c.primary,
          borderRadius: BorderRadius.circular(size * .28),
        ),
        child: Icon(Icons.check_rounded, size: size * .72, color: c.onPrimary),
      ),
    );
  }
}

/// A flat tonal surface with a hairline edge: no shadow, no ornament.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 16,
    this.color,
    this.borderColor,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Color? borderColor;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Material(
      color: color ?? c.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: borderColor ?? c.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}
