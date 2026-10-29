import 'package:flutter/material.dart';
import 'package:farash/app/soft.dart';

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

/// A raised soft tile with a hairline edge: the one container on the
/// soft ground (see soft.dart).
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = Soft.tileRadius,
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
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: borderColor == null
          ? Soft.hairline(context)
          : BorderSide(color: borderColor!),
    );
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        color: color ?? Soft.ground(context),
        shadows: Soft.raised(context, depth: 4),
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
