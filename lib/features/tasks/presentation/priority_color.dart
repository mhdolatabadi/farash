import 'package:flutter/widgets.dart';
import 'package:farash/app/palette.dart';
import 'package:farash/features/tasks/data/task.dart';

/// The priority's color in the current theme, from the palette rather than
/// one fixed hex, so it keeps its contrast by day and by night.
extension PriorityColor on TaskPriority {
  Color colorIn(BuildContext context) =>
      FarashGlassColors.of(context).priorities[level - 1];
}
