import 'package:flutter/material.dart';
import 'package:farash/core/api/api_client.dart';
import 'package:farash/core/calendar/time_zone.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/progress/progress.dart';
import 'package:farash/features/progress/week_report.dart';

/// A quiet summary in the navigation; details open only on request.
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
    final progress = _progress;
    if (_error != null) {
      return ListTile(
        leading: const Icon(Icons.cloud_off_outlined),
        title: const Text('پیشرفت من'),
        subtitle: Text(_error!),
        onTap: _load,
      );
    }
    return ListTile(
      leading: const Icon(Icons.insights_outlined),
      title: const Text('پیشرفت من'),
      subtitle: progress == null
          ? const Text('در حال دریافت…')
          : Text(
              'سطح ${persianDigits(progress.level)} · '
              '${persianDigits(progress.xp)} امتیاز · '
              '${persianDigits(progress.weeklyDays)} از '
              '${persianDigits(progress.weeklyGoal)} روز',
            ),
      onTap: progress == null ? null : _open,
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
    return Scaffold(
      appBar: AppBar(title: const Text('پیشرفت من')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('قدم‌های کوچک، پیشرفت ماندگار', style: text.titleLarge),
                const SizedBox(height: 24),
                Text(
                  'سطح ${persianDigits(_progress.level)}',
                  style: text.headlineMedium,
                ),
                Text(
                  '${persianDigits(_progress.xp)} امتیاز · '
                  '${persianDigits(_progress.completed)} کار انجام‌شده',
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: _progress.levelXp / 100,
                  semanticsLabel:
                      'پیشرفت سطح، '
                      '${persianDigits(_progress.levelXp)} از ۱۰۰',
                ),
                const SizedBox(height: 8),
                Text(
                  '${persianDigits(100 - _progress.levelXp)} امتیاز '
                  'تا سطح بعد',
                ),
                const SizedBox(height: 32),
                if (_progress.weekReport case final report?) ...[
                  WeeklyProgressReport(report: report),
                  const SizedBox(height: 24),
                ],
                Text('هدف هفتگی', style: text.titleLarge),
                const SizedBox(height: 8),
                Text(
                  '${persianDigits(_progress.weeklyDays)} روز فعال این هفته؛ '
                  'هر روز با انجام حداقل یک کار.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  key: ValueKey((_progress.weeklyGoal, _saving)),
                  initialValue: _progress.weeklyGoal,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'روزهای هدف'),
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
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'هفته از شنبه شروع می‌شود. غیبت جریمه ندارد؛ '
                  'امتیازهای قبلی با شروع هفتهٔ تازه باقی می‌مانند.',
                ),
                const SizedBox(height: 32),
                Text('نشان‌ها', style: text.titleLarge),
                const SizedBox(height: 8),
                for (final badge in _badges.entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      _progress.badges.contains(badge.key)
                          ? Icons.verified_outlined
                          : Icons.lock_outline,
                    ),
                    title: Text(badge.value.$1),
                    subtitle: Text(badge.value.$2),
                    trailing: Text(
                      _progress.badges.contains(badge.key)
                          ? 'دریافت‌شده'
                          : 'در پیش رو',
                    ),
                  ),
                const SizedBox(height: 24),
                const Text(
                  'هر کار تکمیل‌شده ۱۰ امتیاز دارد. بازگرداندن یا حذف '
                  'آن کار، امتیاز و نشان وابسته را هم بازمی‌گرداند. '
                  'زیرکارهای تکمیل‌شده هم حساب می‌شوند.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
