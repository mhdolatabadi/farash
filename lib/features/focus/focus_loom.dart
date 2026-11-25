import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Original geometric carpet artwork that progresses with a Pomodoro.
///
/// Ten reveal stages correspond to the real elapsed fraction of the session.
/// At zero the frame and warp threads stay visible, but not a single knot is
/// woven. A task title supplies a stable motif seed within this client.
class FocusLoom extends StatelessWidget {
  const FocusLoom({
    super.key,
    required this.progress,
    this.patternSeed = '',
  });

  final double progress;
  final String patternSeed;

  int get stages => (progress.clamp(0.0, 1.0) * 10).ceil().clamp(0, 10);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'فرش تمرکز: ${_digits(stages)} از ۱۰ مرحله بافته شد',
      image: true,
      excludeSemantics: true,
      child: AspectRatio(
        aspectRatio: 1.22,
        child: CustomPaint(
          painter: _LoomPainter(
            stages: stages,
            seed: patternSeed.hashCode,
            ink: colors.onSurface,
            thread: colors.outlineVariant,
            frame: colors.onSurfaceVariant,
            main: colors.primary,
            alternate: colors.tertiary,
            ground: colors.primaryContainer,
          ),
        ),
      ),
    );
  }
}

String _digits(int value) => '$value'
    .replaceAll('0', '۰')
    .replaceAll('1', '۱')
    .replaceAll('2', '۲')
    .replaceAll('3', '۳')
    .replaceAll('4', '۴')
    .replaceAll('5', '۵')
    .replaceAll('6', '۶')
    .replaceAll('7', '۷')
    .replaceAll('8', '۸')
    .replaceAll('9', '۹');

class _LoomPainter extends CustomPainter {
  const _LoomPainter({
    required this.stages,
    required this.seed,
    required this.ink,
    required this.thread,
    required this.frame,
    required this.main,
    required this.alternate,
    required this.ground,
  });

  final int stages;
  final int seed;
  final Color ink;
  final Color thread;
  final Color frame;
  final Color main;
  final Color alternate;
  final Color ground;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final width = size.width;
    final height = size.height;
    final left = width * .13;
    final right = width * .87;
    final top = height * .10;
    final bottom = height * .88;
    final rug = Rect.fromLTRB(left + 7, top + 9, right - 7, bottom - 9);
    final rail = math.max(5.0, width * .027);

    // The rails and unfinished vertical warp remain when progress is zero.
    final wood = Paint()
      ..color = frame
      ..strokeCap = StrokeCap.round
      ..strokeWidth = rail;
    canvas.drawLine(
      Offset(left, top - 8),
      Offset(left, bottom + 12),
      wood,
    );
    canvas.drawLine(
      Offset(right, top - 8),
      Offset(right, bottom + 12),
      wood,
    );
    wood.strokeWidth = rail * 1.6;
    canvas.drawLine(
      Offset(left - 9, top),
      Offset(right + 9, top),
      wood,
    );
    canvas.drawLine(
      Offset(left - 9, bottom),
      Offset(right + 9, bottom),
      wood,
    );

    final warp = Paint()
      ..color = thread
      ..strokeWidth = 1;
    for (var i = 0; i <= 31; i++) {
      final x = rug.left + rug.width * i / 31;
      canvas.drawLine(
        Offset(x, rug.top),
        Offset(x, rug.bottom),
        warp,
      );
    }

    // Rows are woven from the bottom up in exactly ten distinct stages.
    // The pattern is generated from geometry rather than a generic texture.
    const columns = 31;
    const rows = 40;
    final visible = stages * (rows ~/ 10);
    if (visible > 0) {
      final cellW = rug.width / columns;
      final cellH = rug.height / rows;
      for (var y = rows - visible; y < rows; y++) {
        for (var x = 0; x < columns; x++) {
          final fx = (x - 15).abs();
          final fy = (y - 19.5).abs();
          final border = x < 3 || x > 27 || y < 3 || y > 36;
          final stripe = x == 4 || x == 26 || y == 4 || y == 35;
          final diamond = fx + fy * .78;
          final motif = seed.abs() % 3;
          final star = ((x * 3 + y * 5 + motif * 7) % 11) < 2;
          final color = border
              ? (star ? alternate : ink)
              : stripe
              ? alternate
              : diamond < 9
              ? (diamond > 6 ? main : ground)
              : ((x + y + motif) % 7 < 2 ? main : ground);
          canvas.drawRect(
            Rect.fromLTWH(
              rug.left + x * cellW,
              rug.top + y * cellH,
              cellW + 0.25,
              cellH + 0.25,
            ),
            Paint()..color = color,
          );
        }
      }

      // A newly finished weft edge is visible above the woven section.
      final edgeY = rug.bottom - visible * cellH;
      canvas.drawLine(
        Offset(rug.left, edgeY),
        Offset(rug.right, edgeY),
        Paint()
          ..color = alternate
          ..strokeWidth = 2,
      );
    }

    // Dots at the rail ends complete the illustration at any stage.
    for (final x in [left, right]) {
      for (final y in [top, bottom]) {
        canvas.drawCircle(Offset(x, y), 2.5, Paint()..color = ink);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LoomPainter oldDelegate) =>
      stages != oldDelegate.stages ||
      seed != oldDelegate.seed ||
      ink != oldDelegate.ink ||
      thread != oldDelegate.thread ||
      frame != oldDelegate.frame ||
      main != oldDelegate.main ||
      alternate != oldDelegate.alternate ||
      ground != oldDelegate.ground;
}
