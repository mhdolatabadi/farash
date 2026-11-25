import 'package:flutter/material.dart';
import 'package:menval/app/palette.dart';

/// Ledger surfaces: paper, a quiet rule and at most one grounded shadow.
/// Public names stay stable while the old inset/neumorphic styling goes away.
abstract final class Soft {
  static const tileRadius = 18.0;

  static Color ground(BuildContext context) =>
      MenvalPaletteColors.of(context).softGround;

  static List<BoxShadow> raised(BuildContext context, {double depth = 5}) {
    final p = MenvalPaletteColors.of(context);
    final distance = (depth / 2).clamp(1.0, 4.0);
    return [
      BoxShadow(
        color: p.softShade.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.28 : 0.10,
        ),
        offset: Offset(0, distance),
        blurRadius: depth * 2,
      ),
    ];
  }

  static BoxDecoration wellDecoration(BuildContext context) {
    final p = MenvalPaletteColors.of(context);
    return BoxDecoration(
      color: p.containerLowest,
      borderRadius: BorderRadius.circular(tileRadius),
      border: Border.fromBorderSide(hairline(context)),
    );
  }

  static BorderSide hairline(BuildContext context) => BorderSide(
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

/// A quiet paper tile; onTap is optional and retains native ink feedback.
class SoftTile extends StatelessWidget {
  const SoftTile({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = Soft.tileRadius,
    this.color,
    this.onTap,
    this.depth = 5,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double depth;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = MenvalPaletteColors.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: Soft.hairline(context),
    );
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        color: color ?? p.containerLowest,
        shadows: depth > 0 ? Soft.raised(context, depth: depth * 0.5) : const [],
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A bounded flat ledger surface for lists, reports and circular timer dials.
class SoftWell extends StatelessWidget {
  const SoftWell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(vertical: 4),
    this.radius = Soft.tileRadius,
    this.circle = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final p = MenvalPaletteColors.of(context);
    final shape = circle
        ? const CircleBorder(side: BorderSide.none)
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    return Material(
      color: p.containerLowest,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: circle
              ? CircleBorder(side: Soft.hairline(context))
              : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(radius),
                  side: Soft.hairline(context),
                ),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
