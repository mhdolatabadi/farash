import 'package:flutter/material.dart';

const listBarHeight = 64.0;

/// A stable toolbar; the subtitle scrolls away without switching titles.
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
    final scaffold = Scaffold.maybeOf(context);
    final extra = (expandedHeight - shrinkOffset).clamp(0.0, expandedHeight);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: EdgeInsets.fromLTRB(inset + 12, topPadding, inset + 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: listBarHeight,
              child: Row(
                children: [
                  if (scaffold?.hasDrawer ?? false)
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).openAppDrawerTooltip,
                      icon: const Icon(Icons.menu_rounded),
                      onPressed: scaffold!.openDrawer,
                    ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: mark,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      header: true,
                      // Large text steps the title down a size so long
                      // names keep more of themselves in the bar; the full
                      // name stays in the tooltip.
                      child: Tooltip(
                        message: title,
                        excludeFromSemantics: true,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              (MediaQuery.textScalerOf(context).scale(1) >= 1.5
                                      ? theme.textTheme.titleMedium
                                      : theme.textTheme.titleLarge)
                                  ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
            if (extra > 0)
              SizedBox(
                height: extra,
                width: double.infinity,
                child: ClipRect(
                  child: Align(
                    alignment: AlignmentDirectional.topStart,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: 12,
                        bottom: 8,
                      ),
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(ListAppBar old) => true;
}
