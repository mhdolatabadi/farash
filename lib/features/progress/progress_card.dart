import 'package:flutter/material.dart';
import 'package:farash/app/soft.dart';
import 'package:farash/app/spacing.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/core/calendar/time_zone.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/progress/progress.dart';
import 'package:farash/features/progress/week_report.dart';
import 'package:farash/features/progress/weekly_challenge.dart';

/// A quiet summary pinned under the navigation: the level, and this
/// week's days against the goal as a thin bar. Details open on request.
class ProgressCard extends StatefulWidget {
  const ProgressCard({super.key, required this.api, required this.token});

  final ApiClient api;
  final String? Function() token;

  @override
  State<ProgressCard> createState() => _ProgressCardState();
}

class _ProgressCardState extends State<ProgressCard>
    with WidgetsBindingObserver {
  PersonalProgress? _progress;
  String? _error;
  String _zone = 'Asia/Tehran';
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.api.progressChanges.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(ProgressCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) {
      oldWidget.api.progressChanges.removeListener(_load);
      widget.api.progressChanges.addListener(_load);
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.api.progressChanges.removeListener(_load);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final token = widget.token();
    if (token == null) return;
    final request = ++_request;
    try {
      final zone = await deviceTimeZone();
      final progress = await widget.api.loadProgress(token, zone);
      if (!mounted || request != _request) return;
      setState(() {
        _zone = zone;
        _progress = progress;
        _error = null;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() => _error = 'پیشرفت دریافت نشد؛ دوباره تلاش کنید.');
    }
  }

  Future<void> _open() async {
    await _load();
    if (!mounted || _progress == null || _error != null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _ProgressPage(
          api: widget.api,
          token: widget.token,
          zone: _zone,
          initial: _progress!,
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final progress = _progress;
    final error = _error;
    final week = progress == null || progress.weeklyGoal <= 0
        ? null
        : (progress.weeklyDays / progress.weeklyGoal).clamp(0.0, 1.0);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: error != null ? _load : (progress == null ? null : _open),
        child: Padding(
          padding: const EdgeInsets.all(Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    error != null
                        ? Icons.cloud_off_outlined
                        : Icons.insights_outlined,
                    size: 16,
                    color: error != null ? muted : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      'پیشرفت من',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (progress != null && error == null)
                    Text(
                      'سطح ${persianDigits(progress.level)}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: muted,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Space.sm),
              if (error != null)
                Text(
                  error,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                )
              else ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: week ?? 0,
                    minHeight: 3,
                    backgroundColor: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  progress == null
                      ? 'در حال دریافت…'
                      : '${persianDigits(progress.weeklyDays)} از '
                            '${persianDigits(progress.weeklyGoal)} روز این هفته · '
                            '${persianDigits(progress.xp)} امتیاز',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

const _badges = {
  'first_step': ('اولین قدم', 'یک کار انجام‌شده'),
  'ten_tasks': ('روی روال', 'ده کار انجام‌شده'),
  'fifty_tasks': ('قدم‌های پیوسته', 'پنجاه کار انجام‌شده'),
  'hundred_tasks': ('صد قدم جلوتر', 'صد کار انجام‌شده'),
  'weekly_goal': ('هفتهٔ موفق', 'رسیدن به هدف همین هفته'),
};

class _ProgressPage extends StatefulWidget {
  const _ProgressPage({
    required this.api,
    required this.token,
    required this.zone,
    required this.initial,
  });

  final ApiClient api;
  final String? Function() token;
  final String zone;
  final PersonalProgress initial;

  @override
  State<_ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<_ProgressPage> {
  Future<void> _saveChallenge(int target) async {
    final token = widget.token();
    if (token == null) throw const ApiException('نشست شما منقضی شده است.');
    final progress = await widget.api.saveWeeklyChallenge(
      token,
      widget.zone,
      target,
    );
    if (mounted) setState(() => _progress = progress);
  }

  late PersonalProgress _progress = widget.initial;
  bool _saving = false;
  String? _error;

  Future<void> _save(int? days) async {
    final token = widget.token();
    if (days == null || token == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final progress = await widget.api.saveProgressGoal(
        token,
        widget.zone,
        days,
      );
      if (mounted) setState(() => _progress = progress);
    } catch (_) {
      if (mounted) setState(() => _error = 'هدف ذخیره نشد؛ دوباره تلاش کنید.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Section titles step below the page title; notes read as asides.
    final section = text.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    final note = text.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('پیشرفت من'),
        actions: [
          // The rules live behind one button instead of under every section.
          IconButton(
            tooltip: 'قواعد امتیاز',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('قواعد امتیاز'),
                content: const Text(
                  'هر کار تکمیل‌شده ۱۰ امتیاز دارد و زیرکارها هم حساب '
                  'می‌شوند. بازگرداندن یا حذف کار، امتیاز و نشانش را هم '
                  'برمی‌گرداند.\n\nهفته از شنبه شروع می‌شود و روز فعال یعنی '
                  'دست‌کم یک کار انجام‌شده. غیبت جریمه ندارد.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('بستن'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.sm,
                Space.gutter,
                Space.xxl,
              ),
              children: [
                _LevelTiles(progress: _progress),
                const SizedBox(height: Space.md),
                SoftTile(
                  padding: const EdgeInsets.all(Space.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('هدف هفتگی', style: section)),
                          Text(
                            '${persianDigits(_progress.weeklyDays)} از '
                            '${persianDigits(_progress.weeklyGoal)} روز فعال',
                            style: note,
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.md),
                      DropdownButtonFormField<int>(
                        key: ValueKey((_progress.weeklyGoal, _saving)),
                        initialValue: _progress.weeklyGoal,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'روزهای هدف',
                        ),
                        items: [
                          for (var day = 1; day <= 7; day++)
                            DropdownMenuItem(
                              value: day,
                              child: Text('${persianDigits(day)} روز در هفته'),
                            ),
                        ],
                        onChanged: _saving ? null : _save,
                      ),
                      if (_saving) const LinearProgressIndicator(),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.sm),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_progress.weekReport case final report?) ...[
                  if (_progress.weeklyTaskGoal case final target?) ...[
                    const SizedBox(height: Space.md),
                    WeeklyChallenge(
                      completed: report.completed,
                      target: target,
                      onSave: _saveChallenge,
                    ),
                  ],
                  const SizedBox(height: Space.md),
                  WeeklyProgressReport(report: report),
                ],
                const SizedBox(height: Space.xl),
                Text('نشان‌ها', style: section),
                const SizedBox(height: Space.sm),
                _Badges(earned: _progress.badges),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Badges as small tiles: earned ones raised, the rest sunk and dim. The
/// condition is in the tooltip and the label, not under every name.
class _Badges extends StatelessWidget {
  const _Badges({required this.earned});
  final Iterable<String> earned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final columns = box.maxWidth >= 420 * scale ? 3 : 2;
        final width = (box.maxWidth - Space.md * (columns - 1)) / columns;
        return Wrap(
          spacing: Space.md,
          runSpacing: Space.md,
          children: [
            for (final badge in _badges.entries)
              SizedBox(
                width: width,
                child: Tooltip(
                  message: badge.value.$2,
                  child: Semantics(
                    label:
                        '${badge.value.$1}، ${badge.value.$2}، '
                        '${earned.contains(badge.key) ? 'دریافت‌شده' : 'در پیش رو'}',
                    excludeSemantics: true,
                    child: () {
                      final got = earned.contains(badge.key);
                      final content = Padding(
                        padding: const EdgeInsets.all(Space.md),
                        child: Row(
                          children: [
                            Icon(
                              got
                                  ? Icons.verified_outlined
                                  : Icons.lock_outline,
                              color: got
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: Space.sm),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(
                                  badge.value.$1,
                                  maxLines: 1,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: got
                                        ? null
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                      return got
                          ? SoftTile(padding: EdgeInsets.zero, child: content)
                          : SoftWell(padding: EdgeInsets.zero, child: content);
                    }(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The level and its points as two raised tiles, side by side unless the
/// text is large.
class _LevelTiles extends StatelessWidget {
  const _LevelTiles({required this.progress});
  final PersonalProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caption = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    final value = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w900,
    );
    final level = SoftTile(
      child: Row(
        children: [
          SizedBox.square(
            dimension: 48,
            child: CircularProgressIndicator(
              value: progress.levelXp / 100,
              strokeWidth: 6,
              strokeCap: StrokeCap.round,
              backgroundColor: theme.colorScheme.outlineVariant,
              semanticsLabel:
                  'پیشرفت سطح، '
                  '${persianDigits(progress.levelXp)} از ۱۰۰',
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('سطح ${persianDigits(progress.level)}', style: value),
                Text(
                  '${persianDigits(100 - progress.levelXp)} امتیاز '
                  'تا سطح بعد',
                  style: caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final points = SoftTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${persianDigits(progress.xp)} امتیاز', style: value),
          Text(
            '${persianDigits(progress.completed)} کار انجام‌شده',
            style: caption,
          ),
        ],
      ),
    );
    if (MediaQuery.textScalerOf(context).scale(1) >= 1.5) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          level,
          const SizedBox(height: Space.md),
          points,
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: level),
          const SizedBox(width: Space.md),
          Expanded(flex: 2, child: points),
        ],
      ),
    );
  }
}
