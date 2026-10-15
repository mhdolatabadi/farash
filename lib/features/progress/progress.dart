class PersonalProgress {
  const PersonalProgress({
    required this.completed,
    required this.xp,
    required this.level,
    required this.levelXp,
    required this.weeklyDays,
    required this.weeklyGoal,
    required this.badges,
    this.weekReport,
  });

  factory PersonalProgress.fromJson(Map<String, dynamic> json) =>
      PersonalProgress(
        completed: json['completed'] as int,
        xp: json['xp'] as int,
        level: json['level'] as int,
        levelXp: json['level_xp'] as int,
        weeklyDays: json['weekly_days'] as int,
        weeklyGoal: json['weekly_goal'] as int,
        badges: List<String>.from(json['badges'] as List),
        weekReport: json['week_report'] is Map<String, dynamic>
            ? ProgressWeekReport.fromJson(
                json['week_report'] as Map<String, dynamic>,
              )
            : null,
      );

  final int completed;
  final int xp;
  final int level;
  final int levelXp;
  final int weeklyDays;
  final int weeklyGoal;
  final List<String> badges;
  final ProgressWeekReport? weekReport;
}

class ProgressWeekReport {
  ProgressWeekReport.fromJson(Map<String, dynamic> json)
    : completed = json['completed'] as int,
      previousCompleted = json['previous_completed'] as int,
      days = [
        for (final day in json['days'] as List)
          ProgressDay.fromJson(day as Map<String, dynamic>),
      ];
  final int completed;
  final int previousCompleted;
  final List<ProgressDay> days;
}

class ProgressDay {
  ProgressDay.fromJson(Map<String, dynamic> json)
    : date = DateTime.parse(json['date'] as String),
      completed = json['completed'] as int,
      future = json['future'] as bool;
  final DateTime date;
  final int completed;
  final bool future;
}
