import 'package:flutter/material.dart';
import 'package:farash/app/motion.dart';

/// Artwork changes stage only from confirmed completed work.
class GardenScene extends StatelessWidget {
  const GardenScene({super.key, this.height = 250, this.completed});
  final double height;
  final int? completed;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: AnimatedSwitcher(
      duration: Motion.of(context, const Duration(milliseconds: 180)),
      child: Image.asset(
        completed != null && completed! >= 10
            ? 'assets/garden/sanctuary.png'
            : 'assets/garden/sanctuary-seed.png',
        key: ValueKey(completed != null && completed! >= 10),
        width: double.infinity,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
    ),
  );
}
