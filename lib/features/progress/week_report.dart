import 'package:flutter/material.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/progress/progress.dart';

/// The summary compares equal local weekdays/time, never a partial week
/// against all seven days of the previous week.
class WeeklyProgressReport extends StatelessWidget {
  const WeeklyProgressReport({super.key, required this.report});
  final ProgressWeekReport report;

  static const _weekdays = [
    'دوشنبه',
    'سه‌شنبه',
    'چهارشنبه',
    'پنجشنبه',
    'جمعه',
    'شنبه',
    'یکشنبه',
  ];

  @override
  Widget build(BuildContext context) {
    final difference = report.completed - report.previousCompleted;
    final comparison = difference == 0
        ? 'برابر با بازهٔ مشابه هفتهٔ قبل'
        : '${persianDigits(difference.abs())} کار '
              '${difference > 0 ? 'بیشتر' : 'کمتر'} از بازهٔ مشابه هفتهٔ قبل';
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: const Text('گزارش این هفته'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${persianDigits(report.completed)} کار انجام‌شده'),
              Text(comparison),
            ],
          ),
        ),
        children: [
          const Text(
            'مقایسه از شنبه تا همین روز و ساعت است. '
            'کارهای بازگردانده‌شده و حذف‌شده حساب نمی‌شوند.',
          ),
          const SizedBox(height: 12),
          for (final day in report.days)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Text(_weekdays[day.date.weekday - 1])),
                  Flexible(
                    child: Text(
                      day.future
                          ? 'هنوز نرسیده'
                          : '${persianDigits(day.completed)} کار',
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
