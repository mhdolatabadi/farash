import 'package:flutter/widgets.dart';
import 'package:menval/app/palette.dart';
import 'package:menval/features/tasks/data/task.dart';

/// The priority's color in the current theme, from the palette rather than
/// one fixed hex, so it keeps its contrast by day and by night.
extension PriorityColor on TaskPriority {
  Color colorIn(BuildContext context) =>
      MenvalPaletteColors.of(context).priorities[level - 1];
}
