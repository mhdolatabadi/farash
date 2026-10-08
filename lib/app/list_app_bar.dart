import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:farash/app/motion.dart';
import 'package:farash/app/palette.dart';

/// The toolbar row of a list's app bar.
const listBarHeight = 64.0;

/// A Material medium top app bar for a list (a project or a view): the name large under the
/// toolbar, collapsing into the toolbar as the list scrolls, and frosted
/// glass behind it once tasks pass beneath.
class ListAppBar extends SliverPersistentHeaderDelegate {
  ListAppBar({
    required this.title,
    required this.subtitle,
    required this.mark,
    required this.actions,
    required this.topPadding,
    required this.inset,
    required this.expandedHeight,
  });

  final String title;
  final String subtitle;
  final Widget mark;
  final List<Widget> actions;
  final double topPadding;
  final double inset;

  /// Room for the large title under the toolbar; zero keeps one row.
  final double expandedHeight;

  @override
  double get minExtent => topPadding + listBarHeight;

  @override
  double get maxExtent => minExtent + expandedHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    final glass = FarashGlassColors.of(context);
    final collapsed = expandedHeight == 0
        ? 1.0
        : (shrinkOffset / expandedHeight).clamp(0.0, 1.0);
    final under = overlapsContent || shrinkOffset > 0;
    final scaffold = Scaffold.maybeOf(context);
    final side = inset + 4;
    final barTitle = expandedHeight == 0
        ? 1.0
        : ((collapsed - 0.6) / 0.4).clamp(0.0, 1.0);
    final largeTitle = (1 - collapsed / 0.6).clamp(0.0, 1.0);
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedOpacity(
          opacity: under ? 1 : 0,
          duration: Motion.of(context, Motion.quick),
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: glass.pane,
                  border: Border(bottom: BorderSide(color: glass.paneBorder)),
                ),
              ),
            ),
          ),
        ),
        PositionedDirectional(
          top: topPadding,
          start: side,
          end: side,
          height: listBarHeight,
          child: Row(
            children: [
              if (scaffold?.hasDrawer ?? false)
                IconButton(
                  tooltip: MaterialLocalizations.of(
                    context,
                  ).openAppDrawerTooltip,
                  icon: const Icon(Icons.menu),
                  onPressed: scaffold!.openDrawer,
                )
              else
                const SizedBox(width: 12),
              const SizedBox(width: 4),
              // One title at a time: the toolbar's appears only as the
              // large one fades away.
              Expanded(
                child: barTitle == 0
                    ? const SizedBox.shrink()
                    : Opacity(
                        opacity: barTitle,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ),
              ...actions,
            ],
          ),
        ),
        if (expandedHeight > 0 && largeTitle > 0)
          PositionedDirectional(
            start: side + 16,
            end: side + 16,
            bottom: 12,
            child: IgnorePointer(
              ignoring: collapsed > 0.5,
              child: Opacity(
                opacity: largeTitle,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        mark,
                        const SizedBox(width: 12),
                        Flexible(
                          child: Semantics(
                            header: true,
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                // At night the title catches the lamp.
                                shadows: [
                                  if (theme.brightness == Brightness.dark)
                                    Shadow(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.45),
                                      blurRadius: 24,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  bool shouldRebuild(ListAppBar old) => true;
}
