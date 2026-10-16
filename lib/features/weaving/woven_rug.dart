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
  const WovenRug({super.key, this.height = 250, this.completed});
  final double height;
  final int? completed;
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
      tween: Tween(end: rows / 50),
      duration: Motion.of(context, const Duration(milliseconds: 320)),
      builder: (context, fraction, _) => CustomPaint(
        painter: _RugPainter(fraction, design),
        size: const Size(150, 200),
      ),
    ),
  );
}

class _RugPainter extends CustomPainter {
  _RugPainter(this.fraction, this.design);
  final double fraction;
  final int design;
  static const palettes = [
    [
      Color(0xFF9D4F3D),
      Color(0xFF286F75),
      Color(0xFF26384E),
      Color(0xFFE4BC78),
    ],
    [
      Color(0xFF286F75),
      Color(0xFFAA6547),
      Color(0xFF26384E),
      Color(0xFFE4BC78),
    ],
    [
      Color(0xFF334862),
      Color(0xFFAD634D),
      Color(0xFF286F75),
      Color(0xFFE4BC78),
    ],
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final colors = palettes[design % palettes.length];
    final cellW = size.width / 31;
    final cellH = size.height / 50;
    final paint = Paint();
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)),
      paint..color = const Color(0xFFEAE0CF),
    );
    // Exposed warp stays pale; only confirmed rows reveal coloured wool.
    for (var x = 0; x < 31; x++) {
      canvas.drawLine(
        Offset((x + .5) * cellW, 0),
        Offset((x + .5) * cellW, size.height),
        paint
          ..color = const Color(0xFFCABDAB)
          ..strokeWidth = .45,
      );
    }
    canvas.save();
    canvas.clipRect(
      Rect.fromLTWH(
        0,
        size.height * (1 - fraction),
        size.width,
        size.height * fraction,
      ),
    );
    for (var y = 0; y < 50; y++) {
      for (var x = 0; x < 31; x++) {
        final edge = [x, 30 - x, y, 49 - y].reduce((a, b) => a < b ? a : b);
        final dx = (x - 15).abs();
        final dy = ((y - 24.5) * .65).abs();
        Color color;
        if (edge < 2) {
          color = colors[2];
        } else if (edge < 5) {
          color = (x + y) % 4 == 0 ? colors[3] : colors[0];
        } else if (edge == 5) {
          color = colors[3];
        } else if (dx + dy < 11) {
          color = dx + dy < 3
              ? colors[3]
              : dx + dy < 7
              ? colors[1]
              : colors[2];
        } else {
          color = (x % 6 == 0 && y % 6 == 0) ? colors[3] : colors[0];
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              x * cellW + .2,
              y * cellH + .15,
              cellW - .4,
              cellH - .3,
            ),
            const Radius.circular(.65),
          ),
          paint
            ..color = color
            ..style = PaintingStyle.fill,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RugPainter old) =>
      old.fraction != fraction || old.design != design;
}
