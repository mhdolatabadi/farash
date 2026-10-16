import 'package:farash/app/atelier.dart';
import 'package:flutter/material.dart';
import 'package:farash/core/text/persian_digits.dart';
import 'package:farash/features/focus/focus_controller.dart';
import 'package:farash/features/weaving/woven_rug.dart';

class FocusView extends StatefulWidget {
  const FocusView({super.key, required this.controller});
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final timer = widget.controller;
      final theme = Theme.of(context);
      final seconds = (timer.remaining.inMilliseconds / 1000).ceil();
      final time =
          '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
      return CustomScrollView(
        key: const PageStorageKey('focus-scroll'),
        slivers: [
          const SliverAppBar(title: Text('وقتِ تمرکز'), floating: true),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: Column(
                    children: [
                      const WovenRug(height: 180),
                      Text(
                        timer.finished
                            ? 'یک مکثِ پربار.'
                            : timer.minutes == 25
                            ? 'فقط همین یک کار.'
                            : 'وقتِ نفس تازه.',
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        timer.minutes == 25
                            ? timer.taskTitle ??
                                  'چند دقیقه برای چیزی که مهم است.'
                            : 'کمی فاصله، بعد یک شروع تازه.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 12),
                      const ThreadRule(),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final item in [
                      (25, 'تمرکز'),
                      (5, 'استراحت کوتاه'),
                      (15, 'استراحت بلند'),
                    ])
                      ChoiceChip(
                        label: Text(item.$2),
                        selected: timer.minutes == item.$1,
                        onSelected: timer.running
                            ? null
                            : (_) => timer.choose(item.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                AtelierPanel(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ThreadRule(),
                      const SizedBox(height: 12),
                      Semantics(
                        label:
                            '${persianDigits(seconds ~/ 60)} دقیقه و ${persianDigits(seconds % 60)} ثانیه باقی مانده',
                        excludeSemantics: true,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            persianDigits(time),
                            textDirection: TextDirection.ltr,
                            style: theme.textTheme.displayLarge?.copyWith(
                              fontSize: 80,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: timer.running
                                ? timer.pause
                                : timer.start,
                            icon: Icon(
                              timer.running
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                            label: Text(
                              timer.running
                                  ? 'مکث'
                                  : timer.finished
                                  ? 'دوباره شروع کن'
                                  : timer.minutes == 25
                                  ? 'شروع تمرکز'
                                  : 'شروع استراحت',
                            ),
                          ),
                          IconButton.outlined(
                            tooltip: 'از نو',
                            onPressed: timer.reset,
                            icon: const Icon(Icons.restart_alt),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        timer.finished
                            ? 'جلسه تمام شد. وقت یک نفس تازه است.'
                            : 'تایمر با جابه‌جایی بین صفحه‌ها ادامه دارد. با بستن برنامه، جلسه پایان می‌یابد.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
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
