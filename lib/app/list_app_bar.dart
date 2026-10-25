import 'package:flutter/material.dart';
import 'package:farash/app/spacing.dart';

const listBarHeight = 64.0;

/// The square the view's mark sits in, whatever its own size.
const _markSlot = 24.0;

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
    final drawer = scaffold?.hasDrawer ?? false;
    // Icon buttons start 4 in so their glyphs sit on the gutter. The mark
    // takes the content keyline beside the menu, or the gutter without
    // one; title and count share one start edge.
    final markStart = drawer ? Space.keyline : Space.gutter;
    final textStart = markStart + _markSlot + Space.md;
    return ColoredBox(
      color: theme.colorScheme.surface,
      // The count rises into the bar's empty lower edge, so it reads with
      // the title; the clip keeps it inside the header as it scrolls away.
      child: ClipRect(
        child: Padding(
          padding: EdgeInsets.fromLTRB(inset, topPadding, inset, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: listBarHeight,
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: Space.xs,
                  ),
                  child: Row(
                    children: [
                      if (drawer)
                        IconButton(
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).openAppDrawerTooltip,
                          icon: const Icon(Icons.menu_rounded),
                          onPressed: scaffold!.openDrawer,
                        ),
                      SizedBox(width: markStart - Space.xs - (drawer ? 48 : 0)),
                      SizedBox(
                        width: _markSlot,
                        child: Center(child: mark),
                      ),
                      const SizedBox(width: Space.md),
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
                                  (MediaQuery.textScalerOf(context).scale(1) >=
                                              1.5
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
              ),
              if (extra > 0)
                SizedBox(
                  height: extra,
                  width: double.infinity,
                  child: OverflowBox(
                    alignment: AlignmentDirectional.topStart,
                    maxHeight: double.infinity,
                    child: Transform.translate(
                      offset: const Offset(0, -Space.md),
                      child: Opacity(
                        opacity: extra / expandedHeight,
                        child: Padding(
                          padding: EdgeInsetsDirectional.only(
                            start: textStart,
                            end: Space.gutter,
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
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(ListAppBar old) => true;
}
