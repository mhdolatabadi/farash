import 'package:flutter/material.dart';
import 'package:menval/app/soft.dart';

/// The compact monochrome mountain mark beside «منوال» in the approved header.
class MenvalMark extends StatelessWidget {
  const MenvalMark({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _MenvalMarkPainter(Theme.of(context).colorScheme.onSurface),
      ),
    ),
  );
}

class _MenvalMarkPainter extends CustomPainter {
  const _MenvalMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = color
      ..strokeWidth = w * .105
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Two interlocking peaks, not a filled badge.
    final path = Path()
      ..moveTo(w * .09, h * .70)
      ..lineTo(w * .32, h * .24)
      ..quadraticBezierTo(w * .37, h * .14, w * .46, h * .24)
      ..lineTo(w * .62, h * .54)
      ..lineTo(w * .72, h * .36)
      ..lineTo(w * .92, h * .70)
      ..quadraticBezierTo(w * .96, h * .78, w * .86, h * .78)
      ..lineTo(w * .65, h * .78)
      ..lineTo(w * .51, h * .55)
      ..lineTo(w * .40, h * .78)
      ..lineTo(w * .15, h * .78);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MenvalMarkPainter oldDelegate) =>
      oldDelegate.color != color;
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
