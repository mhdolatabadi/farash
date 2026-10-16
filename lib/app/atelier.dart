import 'package:flutter/material.dart';

/// The house mark is a woven diamond, shared by navigation and page furniture.
class WeaveMark extends StatelessWidget {
  const WeaveMark({super.key, this.size = 28, this.color});
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _MarkPainter(color ?? Theme.of(context).colorScheme.primary),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * .075
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    for (final scale in [.9, .48]) {
      final r = size.width * scale / 2;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - r)
          ..lineTo(c.dx + r, c.dy)
          ..lineTo(c.dx, c.dy + r)
          ..lineTo(c.dx - r, c.dy)
          ..close(),
        paint,
      );
    }
    canvas.drawCircle(c, size.width * .07, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color;
}

/// Paper-like tonal material with a warm edge and a small, deliberate lift.
class AtelierPanel extends StatelessWidget {
  const AtelierPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 24,
    this.color,
    this.lifted = true,
    this.borderColor,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final bool lifted;
  final Color? borderColor;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: lifted
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? .12 : .045),
                  blurRadius: 22,
                  offset: const Offset(0, 7),
                ),
              ]
            : [],
      ),
      child: Material(
        color: color ?? c.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(
            color: borderColor ?? c.outlineVariant.withValues(alpha: .7),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class ThreadRule extends StatelessWidget {
  const ThreadRule({super.key});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Divider(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10),
        child: WeaveMark(size: 14),
      ),
      Expanded(
        child: Divider(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ],
  );
}
