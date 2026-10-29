import 'package:flutter/material.dart';
import 'package:farash/app/palette.dart';

/// The soft surfaces of the main destinations: tiles that rise off the
/// ground and wells sunk into it. Each also carries a hairline, so an edge
/// never depends on a shadow alone.
abstract final class Soft {
  static const tileRadius = 22.0;

  /// The ground the main destinations are painted on.
  static Color ground(BuildContext context) =>
      FarashPaletteColors.of(context).softGround;

  static List<BoxShadow> raised(BuildContext context, {double depth = 5}) {
    final p = FarashPaletteColors.of(context);
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
    final p = FarashPaletteColors.of(context);
    return BoxDecoration(
      color: Color.lerp(p.softGround, p.softShade, 0.22),
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
        color: color ?? Soft.ground(context),
        shadows: Soft.raised(context, depth: depth),
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
    final p = FarashPaletteColors.of(context);
    return CustomPaint(
      foregroundPainter: _InsetShadow(
        light: p.softLight,
        shade: p.softShade,
        radius: radius,
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
        child: ColoredBox(
          color: p.softGround,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Paints the inner shadows of a well: dark from the top start corner,
/// light from the bottom end, inside the shape only.
class _InsetShadow extends CustomPainter {
  _InsetShadow({
    required this.light,
    required this.shade,
    required this.radius,
    required this.circle,
    required this.edge,
  });

  final Color light;
  final Color shade;
  final Color edge;
  final double radius;
  final bool circle;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = circle
        ? (Path()..addOval(rect))
        : (Path()
            ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius))));
    canvas.save();
    canvas.clipPath(shape);
    void cast(Color color, Offset offset) {
      final outside = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect.inflate(24))
        ..addPath(shape, Offset.zero);
      canvas.drawPath(
        outside.shift(offset),
        Paint()
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    cast(shade, const Offset(4, 4));
    cast(light, const Offset(-4, -4));
    canvas.restore();
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = edge,
    );
  }

  @override
  bool shouldRepaint(_InsetShadow old) =>
      old.light != light ||
      old.shade != shade ||
      old.edge != edge ||
      old.radius != radius ||
      old.circle != circle;
}
