import 'package:flutter/material.dart';
import 'package:menval/app/soft.dart';
import 'package:menval/app/spacing.dart';
import 'package:menval/core/text/persian_digits.dart';
import 'package:menval/features/focus/focus_controller.dart';

class FocusView extends StatefulWidget {
  const FocusView({
    super.key,
    required this.controller,
    this.beforeStart,
    this.beforePause,
    this.timeLinked = false,
  });
  final Future<bool> Function()? beforeStart;
  final Future<bool> Function()? beforePause;
  final bool timeLinked;
  final FocusController controller;
  @override
  State<FocusView> createState() => _FocusViewState();
}

class _FocusViewState extends State<FocusView> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.controller.refresh();
  }

  Future<void> _toggle() async {
    final timer = widget.controller;
    if (timer.running) {
      if (await (widget.beforePause?.call() ?? Future.value(true)) && mounted) {
        timer.pause();
      }
    } else if (await (widget.beforeStart?.call() ?? Future.value(true)) &&
        mounted) {
      timer.start();
    }
  }

  Future<void> _reset() async {
    final timer = widget.controller;
    // Do not silently discard a session with elapsed time.
    if (!timer.finished && (timer.running || timer.progress > 0)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('شروع دوبارهٔ نوبت؟'),
          content: const Text(
            'زمان سپری‌شدهٔ این نوبت از دست می‌رود. می‌خواهید از نو شروع کنید؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('از نو'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    if (await (widget.beforePause?.call() ?? Future.value(true)) && mounted) {
      timer.reset();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final timer = widget.controller;
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final work = timer.minutes == 25;
      return ColoredBox(
        color: Soft.ground(context),
        child: CustomScrollView(
          key: const PageStorageKey('focus-scroll'),
          slivers: [
            SliverAppBar(
              backgroundColor: Soft.ground(context),
              title: Text(
                'تمرکز',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              floating: true,
            ),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      Space.sm,
                      Space.gutter,
                      Space.xxl, // Focus must not compete with a global capture action.
                    ),
                    child: Column(
                      children: [
                        // One segmented control when the labels fit on a
                        // line; wrapping chips at large text or narrow widths.
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final modes = [
                              (25, 'تمرکز'),
                              (5, 'استراحت کوتاه'),
                              (15, 'استراحت بلند'),
                            ];
                            final scale = MediaQuery.textScalerOf(
                              context,
                            ).scale(1);
                            if (constraints.maxWidth >= 330 * scale) {
                              return SizedBox(
                                width: double.infinity,
                                child: SegmentedButton<int>(
                                  showSelectedIcon: false,
                                  segments: [
                                    for (final (value, label) in modes)
                                      ButtonSegment(
                                        value: value,
                                        label: Text(label, maxLines: 1),
                                      ),
                                  ],
                                  selected: {timer.minutes},
                                  onSelectionChanged: timer.running
                                      ? null
                                      : (value) => timer.choose(value.first),
                                ),
                              );
                            }
                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                for (final (value, label) in modes)
                                  ChoiceChip(
                                    label: Text(label),
                                    selected: timer.minutes == value,
                                    onSelected: timer.running
                                        ? null
                                        : (_) => timer.choose(value),
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: Space.xl),
                        _LedgerClock(timer: timer),
                        const SizedBox(height: 20),
                        Text(
                          timer.finished
                              ? work
                                    ? 'جلسه تمام شد. یک استراحت کوتاه کنید.'
                                    : 'استراحت تمام شد.'
                              : work
                              ? timer.taskTitle ?? 'بدون کار مشخص'
                              : 'استراحت',
                          textAlign: TextAlign.center,
                          maxLines:
                              MediaQuery.textScalerOf(context).scale(1) >= 1.5
                              ? 4
                              : 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 24),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: Space.md,
                          runSpacing: Space.md,
                          children: [
                            Tooltip(
                              message: 'بازنشانی نوبت تمرکز',
                              child: Semantics(
                                button: true,
                                label: 'بازنشانی نوبت تمرکز',
                                excludeSemantics: true,
                                child: SizedBox.square(
                                  dimension: 56,
                                  child: SoftTile(
                                    radius: 18,
                                    padding: EdgeInsets.zero,
                                    onTap: _reset,
                                    child: Center(
                                      child: Icon(
                                        Icons.restart_alt,
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(160, 64),
                                textStyle: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              onPressed: _toggle,
                              icon: Icon(
                                timer.running
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                              label: Text(
                                timer.running
                                    ? 'مکث'
                                    : timer.finished
                                    ? 'دوباره شروع کنید'
                                    : work
                                    ? 'شروع تمرکز'
                                    : 'شروع استراحت',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        Text(
                          widget.timeLinked && work
                              ? 'شروع تمرکز، ثبت زمان این کار را هم فعال می‌کند. برای پایان زودتر مکث کنید؛ ثبت سرور حداکثر تا پایان نوبت ادامه دارد.'
                              : 'تایمر با جابه‌جایی بین صفحه‌ها ادامه دارد و با بازکردن دوبارهٔ برنامه بازیابی می‌شود.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// The focus period reads like a page in a daybook instead of an inset dial.
class _LedgerClock extends StatelessWidget {
  const _LedgerClock({required this.timer});

  final FocusController timer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final seconds = (timer.remaining.inMilliseconds / 1000).ceil();
    final clock = persianDigits(
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}',
    );
    final label = timer.minutes == 25 ? 'نوبت تمرکز' : 'زمان استراحت';
    final state = timer.finished
        ? 'نوبت تمام شد'
        : timer.running
        ? 'در حال اجرا'
        : 'آمادهٔ شروع';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        Space.xl,
        Space.xl,
        Space.xl,
        Space.lg,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                state,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: timer.running
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xl),
          Semantics(
            label:
                '${persianDigits(seconds ~/ 60)} دقیقه و ${persianDigits(seconds % 60)} ثانیه باقی مانده',
            excludeSemantics: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                clock,
                textDirection: TextDirection.ltr,
                style: theme.textTheme.displayLarge?.copyWith(
                  fontSize: 84,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                  color: colors.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.xl),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: timer.progress,
              minHeight: 6,
              color: colors.primary,
              backgroundColor: colors.outlineVariant,
            ),
          ),
          const SizedBox(height: Space.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              'از ${persianDigits(timer.minutes)} دقیقه',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
