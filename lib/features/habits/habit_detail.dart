import 'package:flutter/material.dart';
import 'package:farash/core/calendar/calendar_scope.dart';
import 'package:farash/core/calendar/calendar_settings.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/habits/habit.dart';
import 'package:farash/features/habits/habit_charts.dart';
import 'package:farash/features/habits/habit_editor.dart';
import 'package:farash/features/habits/habit_stats.dart';
import 'package:farash/features/habits/habits_controller.dart';
import 'package:farash/features/habits/habits_view.dart';

enum _Action { archive, delete }

/// Loop's habit screen: overview, strength, history, calendar, streaks and
/// frequency, stacked in sections under the habit's colour.
class HabitDetailScreen extends StatefulWidget {
  const HabitDetailScreen({
    super.key,
    required this.controller,
    required this.habitId,
  });

  final HabitsController controller;
  final String habitId;

  @override
  State<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends State<HabitDetailScreen> {
  Bucket _scoreBucket = Bucket.week, _historyBucket = Bucket.week;

  HabitsController get _c => widget.controller;

  Future<void> _act(Habit habit, _Action action) async {
    switch (action) {
      case _Action.archive:
        final ok = await _c.update(
          habit,
          HabitDraft(archived: !habit.archived),
        );
        if (ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                habit.archived ? 'از بایگانی خارج شد.' : 'بایگانی شد.',
              ),
            ),
          );
        }
      case _Action.delete:
        final yes = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('حذف عادت'),
            content: Text(
              '«${habit.name}» و همهٔ روزهای ثبت‌شده‌اش حذف شود؟ '
              'این کار برگشت‌پذیر نیست؛ برای کنار گذاشتن موقت، بایگانی کنید.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('انصراف'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حذف'),
              ),
            ],
          ),
        );
        if (yes == true && mounted) {
          final navigator = Navigator.of(context);
          if (await _c.delete(habit)) navigator.pop();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_c, CalendarScope.of(context)]),
      builder: (context, _) {
        final habit = _c.byId(widget.habitId);
        if (habit == null) {
          return Scaffold(appBar: AppBar());
        }
        final stats = _c.stats(habit);
        final settings = CalendarScope.of(context);
        final color = habitColor(context, habit.color);
        final onColor =
            ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : Colors.black;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: color,
            foregroundColor: onColor,
            iconTheme: IconThemeData(color: onColor),
            actionsIconTheme: IconThemeData(color: onColor),
            titleTextStyle: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: onColor),
            title: Text(
              habit.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                tooltip: 'ویرایش',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<Habit>(
                    fullscreenDialog: true,
                    builder: (_) => HabitEditor(controller: _c, habit: habit),
                  ),
                ),
              ),
              PopupMenuButton<_Action>(
                tooltip: 'بیشتر',
                onSelected: (a) => _act(habit, a),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _Action.archive,
                    child: Text(habit.archived ? 'خروج از بایگانی' : 'بایگانی'),
                  ),
                  const PopupMenuItem(
                    value: _Action.delete,
                    child: Text('حذف'),
                  ),
                ],
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  _Subtitle(habit: habit, color: color),
                  _Section(
                    title: 'نمای کلی',
                    color: color,
                    child: _Overview(stats: stats, color: color),
                  ),
                  if (habit.isNumeric)
                    _Section(
                      title: 'هدف',
                      color: color,
                      child: _Targets(
                        stats: stats,
                        settings: settings,
                        color: color,
                      ),
                    ),
                  _Section(
                    title: 'قدرت عادت',
                    color: color,
                    trailing: _BucketMenu(
                      value: _scoreBucket,
                      onChanged: (b) => setState(() => _scoreBucket = b),
                    ),
                    child: ScoreChart(
                      stats: stats,
                      bucket: _scoreBucket,
                      settings: settings,
                      color: color,
                    ),
                  ),
                  _Section(
                    title: 'تاریخچه',
                    color: color,
                    trailing: _BucketMenu(
                      value: _historyBucket,
                      skipDay: true,
                      onChanged: (b) => setState(() => _historyBucket = b),
                    ),
                    child: HistoryChart(
                      stats: stats,
                      bucket: _historyBucket,
                      settings: settings,
                      color: color,
                    ),
                  ),
                  _Section(
                    title: 'تقویم',
                    color: color,
                    child: HabitCalendar(
                      stats: stats,
                      settings: settings,
                      color: color,
                      onDay: (d) => recordDay(context, _c, habit, d),
                    ),
                  ),
                  _Section(
                    title: 'بهترین زنجیره‌ها',
                    color: color,
                    child: StreakList(
                      stats: stats,
                      settings: settings,
                      color: color,
                    ),
                  ),
                  _Section(
                    title: 'تکرار',
                    color: color,
                    child: FrequencyChart(
                      stats: stats,
                      settings: settings,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.habit, required this.color});

  final Habit habit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (habit.question.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                habit.question,
                style: theme.textTheme.titleMedium?.copyWith(color: color),
              ),
            ),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _Fact(
                icon: Icons.repeat_rounded,
                text: habit.isNumeric
                    ? habit.targetLabel
                    : habit.frequencyLabel,
                color: muted,
              ),
              if (habit.archived)
                _Fact(
                  icon: Icons.archive_outlined,
                  text: 'بایگانی‌شده',
                  color: muted,
                ),
            ],
          ),
          if (habit.notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(habit.notes, style: theme.textTheme.bodyMedium),
            ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 6),
      Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
      ),
    ],
  );
}

/// A titled block separated by a hairline, instead of nested cards.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.color,
    required this.child,
    this.trailing,
  });

  final String title;
  final Color color;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _BucketMenu extends StatelessWidget {
  const _BucketMenu({
    required this.value,
    required this.onChanged,
    this.skipDay = false,
  });

  final Bucket value;
  final ValueChanged<Bucket> onChanged;
  final bool skipDay;

  @override
  Widget build(BuildContext context) => PopupMenuButton<Bucket>(
    tooltip: 'بازهٔ نمودار',
    initialValue: value,
    onSelected: onChanged,
    itemBuilder: (context) => [
      for (final b in Bucket.values)
        if (!skipDay || b != Bucket.day)
          PopupMenuItem(value: b, child: Text(bucketLabels[b]!)),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(bucketLabels[value]!),
          const Icon(Icons.arrow_drop_down_rounded),
        ],
      ),
    ),
  );
}

String _percent(double v) => persianDigits('${(v * 100).round()}٪');

String _change(double v) {
  final points = (v * 100).round();
  // Isolated left-to-right so the sign stays in front of the number.
  return persianDigits('\u2066${points > 0 ? '+' : ''}$points٪\u2069');
}

class _Overview extends StatelessWidget {
  const _Overview({required this.stats, required this.color});

  final HabitStats stats;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = stats.currentScore;
    final total = stats.total(stats.from, stats.today);
    final streak = stats.currentStreak?.length ?? 0;
    Widget metric(String value, String label, {Color? tint}) => Expanded(
      child: Semantics(
        label: '$label: $value',
        excludeSemantics: true,
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: tint ?? color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Semantics(
            label: 'قدرت: ${_percent(now)}',
            excludeSemantics: true,
            child: Column(
              children: [
                ScoreRing(score: now, color: color, size: 56, stroke: 7),
                const SizedBox(height: 4),
                Text(
                  _percent(now),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        metric(_change(now - stats.score(stats.today - 30)), 'نسبت به ماه پیش'),
        metric(
          _change(now - stats.score(stats.today - 365)),
          'نسبت به سال پیش',
        ),
        metric(
          stats.habit.isNumeric
              ? formatAmount(total)
              : persianDigits(total.round()),
          stats.habit.isNumeric ? 'مجموع' : 'بار انجام',
        ),
        metric(persianDigits(streak), 'زنجیرهٔ کنونی'),
      ],
    );
  }
}

/// Progress toward a measurable habit's target over today, this week,
/// this month and this year, with the target scaled to each span.
class _Targets extends StatelessWidget {
  const _Targets({
    required this.stats,
    required this.settings,
    required this.color,
  });

  final HabitStats stats;
  final CalendarSettings settings;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final habit = stats.habit;
    final daily = habit.targetValue / habit.freqDen;
    final rows = [
      ('امروز', Bucket.day),
      ('این هفته', Bucket.week),
      ('این ماه', Bucket.month),
      ('امسال', Bucket.year),
    ];
    return Column(
      children: [
        for (final (label, bucket) in rows)
          () {
            final start = bucketStart(bucket, stats.today, settings);
            final span = switch (bucket) {
              Bucket.day => 1,
              Bucket.week => 7,
              _ =>
                bucketStart(
                      bucket,
                      // The first day after this span.
                      start + (bucket == Bucket.month ? 32 : 367),
                      settings,
                    ) -
                    start,
            };
            final goal = habit.freqDen == 1 || span < habit.freqDen
                ? daily * span
                : habit.targetValue * (span / habit.freqDen);
            final done = stats.total(start, stats.today);
            final fraction = goal <= 0 ? 1.0 : (done / goal).clamp(0.0, 1.0);
            final over = habit.target == HabitTarget.atMost && done > goal;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Semantics(
                label:
                    '$label: ${formatAmount(done)} از ${formatAmount(goal)} ${habit.unit}',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(label, style: theme.textTheme.bodyMedium),
                        ),
                        Text(
                          '${formatAmount(done)} / ${formatAmount(goal)} ${habit.unit}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: over ? theme.colorScheme.error : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 8,
                        color: over ? theme.colorScheme.error : color,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }(),
      ],
    );
  }
}
