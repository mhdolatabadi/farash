import 'package:flutter/material.dart';

/// Marks a row whose secondary controls (drag handles, row menus) show only
/// while it is hovered or holds focus, on pointer platforms. On touch
/// platforms they always show, so nothing hides behind a hover.
class HoverRegion extends StatefulWidget {
  const HoverRegion({super.key, required this.child});

  final Widget child;

  @override
  State<HoverRegion> createState() => _HoverRegionState();
}

class _HoverRegionState extends State<HoverRegion> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: _HoverScope(active: _hovered || _focused, child: widget.child),
    ),
  );
}

class _HoverScope extends InheritedWidget {
  const _HoverScope({required this.active, required super.child});

  final bool active;

  @override
  bool updateShouldNotify(_HoverScope old) => old.active != active;
}

/// A control that fades in with its [HoverRegion]. It keeps its size and
/// stays reachable by keyboard, so revealing it never shifts the layout.
class HoverReveal extends StatelessWidget {
  const HoverReveal({super.key, required this.child});

  final Widget child;

  static bool isTouch(BuildContext context) =>
      switch (Theme.of(context).platform) {
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.fuchsia => true,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    if (isTouch(context)) return child;
    final active =
        context.dependOnInheritedWidgetOfExactType<_HoverScope>()?.active ??
        true;
    return AnimatedOpacity(
      opacity: active ? 1 : 0,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 120),
      child: child,
    );
  }
}
