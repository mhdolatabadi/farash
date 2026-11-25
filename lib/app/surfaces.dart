import 'package:flutter/material.dart';
import 'package:menval/app/soft.dart';

/// The Persian letter «م» is a small signet for Menval, not a generic task tick.
class MenvalMark extends StatelessWidget {
  const MenvalMark({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.primary,
          borderRadius: BorderRadius.circular(size * 0.24),
        ),
        child: Text(
          'م',
          textDirection: TextDirection.rtl,
          style: TextStyle(
            fontFamily: 'Vazirmatn',
            color: colors.onPrimary,
            height: 1,
            fontWeight: FontWeight.w900,
            fontSize: size * 0.61,
          ),
        ),
      ),
    );
  }
}

/// A restrained bordered panel on the Ledger page.
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
        color: color ?? Theme.of(context).colorScheme.surfaceContainerLowest,
        shadows: Soft.raised(context, depth: 2),
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
