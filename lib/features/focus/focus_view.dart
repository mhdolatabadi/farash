import 'package:flutter/material.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/focus/focus_controller.dart';

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
    if (await (widget.beforePause?.call() ?? Future.value(true)) && mounted) {
      widget.controller.reset();
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final timer = widget.controller;
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final seconds = (timer.remaining.inMilliseconds / 1000).ceil();
      final time =
          '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
      final work = timer.minutes == 25;
      return CustomScrollView(
        key: const PageStorageKey('focus-scroll'),
        slivers: [
          SliverAppBar(
            title: Text(
              'تمرکز',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            floating: true,
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
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
                      const SizedBox(height: 32),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final size = constraints.maxWidth.clamp(200.0, 280.0);
                          return SizedBox.square(
                            dimension: size,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CircularProgressIndicator(
                                  value: timer.progress,
                                  strokeWidth: 10,
                                  strokeCap: StrokeCap.round,
                                  backgroundColor:
                                      colors.surfaceContainerHighest,
                                ),
                                Center(
                                  child: Semantics(
                                    label:
                                        '${persianDigits(seconds ~/ 60)} دقیقه و ${persianDigits(seconds % 60)} ثانیه باقی مانده',
                                    excludeSemantics: true,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            persianDigits(time),
                                            textDirection: TextDirection.ltr,
                                            style: theme.textTheme.displayLarge
                                                ?.copyWith(
                                                  fontSize: size * .23,
                                                  fontWeight: FontWeight.w700,
                                                  fontFeatures: const [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                          ),
                                        ),
                                        Text(
                                          'از ${persianDigits(timer.minutes)} دقیقه',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: colors.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton.filledTonal(
                            tooltip: 'از نو',
                            iconSize: 24,
                            style: IconButton.styleFrom(
                              minimumSize: const Size(56, 56),
                            ),
                            onPressed: _reset,
                            icon: const Icon(Icons.restart_alt),
                          ),
                          const SizedBox(width: 16),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(160, 64),
                              textStyle: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
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
                            : 'تایمر با جابه‌جایی بین صفحه‌ها ادامه دارد. با بستن برنامه، جلسه پایان می‌یابد.',
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
      );
    },
  );
}
