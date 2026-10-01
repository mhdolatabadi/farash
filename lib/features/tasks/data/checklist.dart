/// TickTick-style checklist items written in a task's description as
/// Markdown task lines: "- [ ] open" and "- [x] done".
class ChecklistItem {
  const ChecklistItem({
    required this.line,
    required this.text,
    required this.done,
  });

  /// The item's line in the description, counted from 0.
  final int line;
  final String text;
  final bool done;
}

final _item = RegExp(r'^(\s*[-*] \[)([ xX])(\]\s?)(.*)$');

List<ChecklistItem> parseChecklist(String description) {
  final lines = description.split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      if (_item.firstMatch(lines[i]) case final match?)
        ChecklistItem(line: i, text: match[4]!.trim(), done: match[2] != ' '),
  ];
}

/// The description with the item on [line] ticked or unticked; other text is
/// kept as written.
String setChecklistItem(String description, int line, bool done) {
  final lines = description.split('\n');
  if (line < 0 || line >= lines.length) return description;
  lines[line] = lines[line].replaceFirstMapped(
    _item,
    (m) => '${m[1]}${done ? 'x' : ' '}${m[3]}${m[4]}',
  );
  return lines.join('\n');
}

/// The description with an open item added after its last line.
String addChecklistItem(String description, String text) {
  final item = '- [ ] ${text.trim()}';
  if (description.trim().isEmpty) return item;
  return description.endsWith('\n')
      ? '$description$item'
      : '$description\n$item';
}

/// The first line worth showing under a task's title: checklist lines are
/// counted separately, so they are skipped.
String descriptionPreview(String description) {
  for (final line in description.split('\n')) {
    final text = line.trim();
    if (text.isNotEmpty && !_item.hasMatch(line)) return text;
  }
  return '';
}
