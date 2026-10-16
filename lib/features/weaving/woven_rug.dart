import 'package:flutter/material.dart';
import 'package:farash/app/motion.dart';
import 'package:farash/core/text/persian_digits.dart';

/// Fifty confirmed completions weave one rug. Undo is reflected automatically.
@immutable
class WeaveProgress {
  const WeaveProgress(this.completed) : assert(completed >= 0);
  final int completed;
  static const rowsPerRug = 50;
  int get rugs => completed ~/ rowsPerRug;
  int get rows => completed % rowsPerRug;
  double get fraction => rows / rowsPerRug;
}

/// Decorative loom artwork; the labelled row strip carries actual progress.
class WovenRug extends StatelessWidget {
  const WovenRug({super.key, this.height = 250});
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Image.asset(
      'assets/weaving/loom.png',
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    ),
  );
}

class RugPattern extends StatelessWidget {
  const RugPattern({super.key, required this.rows, this.design = 0});
  final int rows;
  final int design;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '${persianDigits(rows)} رج از ۵۰ رج بافته شده',
    child: TweenAnimationBuilder<double>(
      tween: Tween(end: (rows / 50).clamp(0, 1)),
      duration: Motion.of(context, const Duration(milliseconds: 320)),
      builder: (context, fraction, _) => AspectRatio(
        aspectRatio: 3 / 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _WarpPainter()),
            ClipRect(
              clipper: _WovenRowsClipper(fraction),
              child: Image.asset(
                'assets/weaving/rug.png',
                fit: BoxFit.fill,
                excludeFromSemantics: true,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _WovenRowsClipper extends CustomClipper<Rect> {
  const _WovenRowsClipper(this.fraction);
  final double fraction;
  @override
  Rect getClip(Size size) => Rect.fromLTWH(
    0,
    size.height * (1 - fraction),
    size.width,
    size.height * fraction,
  );
  @override
  bool shouldReclip(_WovenRowsClipper old) => old.fraction != fraction;
}

class _WarpPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeWidth = .65;
    for (var x = 1; x < 36; x++) {
      canvas.drawLine(
        Offset(x * size.width / 36, 0),
        Offset(x * size.width / 36, size.height),
        paint..color = const Color(0xFFD4C5AE),
      );
    }
  }

  @override
  bool shouldRepaint(_WarpPainter old) => false;
}
