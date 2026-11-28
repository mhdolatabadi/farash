import 'package:flutter/material.dart';
import 'package:menval/app/palette.dart';
import 'package:menval/app/press_depth.dart';

/// The soft surfaces of the main destinations: tiles that rise off the
/// ground and wells sunk into it. Each also carries a hairline, so an edge
/// never depends on a shadow alone.
abstract final class Soft {
  static const tileRadius = 22.0;

  /// The ground the main destinations are painted on.
  static Color ground(BuildContext context) =>
      MenvalPaletteColors.of(context).softGround;

  static Color surface(BuildContext context) =>
      MenvalPaletteColors.of(context).surface;

  static Color inset(BuildContext context) =>
      Theme.of(context).colorScheme.primaryContainer;

  static List<BoxShadow> raised(BuildContext context, {double depth = 5}) {
    final p = MenvalPaletteColors.of(context);
    return [
      BoxShadow(
        color: p.softShade,
        offset: Offset(depth, depth),
        blurRadius: depth * 2.4,
      ),
      BoxShadow(
        color: p.softLight,
        offset: Offset(-depth, -depth),
        blurRadius: depth * 2.4,
      ),
    ];
  }

  /// A well's flat form, for slivers that cannot carry [SoftWell]'s inner
  /// shadows: a touch darker than the ground, with the hairline.
  static BoxDecoration wellDecoration(BuildContext context) {
    return BoxDecoration(
      color: inset(context),
      borderRadius: BorderRadius.circular(tileRadius),
      border: Border.fromBorderSide(hairline(context)),
    );
  }

  static BorderSide hairline(BuildContext context) => BorderSide(
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
  );
}

/// A raised tile on the soft ground; tappable when [onTap] is set.
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

  /// How far the tile stands off the ground; small buttons stand lower.
  final double depth;

  /// Fills the tile, as for an active button; the ground otherwise.
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: color == null ? Soft.hairline(context) : BorderSide.none,
    );
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        color: color ?? Soft.surface(context),
        shadows: Soft.raised(context, depth: depth),
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: PressDepth(
          enabled: onTap != null,
          borderRadius: BorderRadius.circular(radius),
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// A well sunk into the soft ground, holding a list or a dial.
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

  /// Round instead of rounded-rectangular, as for the focus dial.
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final p = MenvalPaletteColors.of(context);
    return CustomPaint(
      foregroundPainter: MenvalInsetPainter(
        light: p.softLight,
        shade: p.softShade,
        borderRadius: BorderRadius.circular(radius),
        circle: circle,
        edge: Soft.hairline(context).color,
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(
          shape: circle
              ? const CircleBorder()
              : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(radius),
                ),
        ),
        // A Material, so rows inside keep their ink and selection.
        child: Material(
          color: Soft.inset(context),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
