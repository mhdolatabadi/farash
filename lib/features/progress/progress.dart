class PersonalProgress {
  const PersonalProgress({
    required this.completed,
    required this.xp,
    required this.level,
    required this.levelXp,
    required this.weeklyDays,
    required this.weeklyGoal,
    required this.badges,
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
      );

  final int completed;
  final int xp;
  final int level;
  final int levelXp;
  final int weeklyDays;
  final int weeklyGoal;
  final List<String> badges;
}
