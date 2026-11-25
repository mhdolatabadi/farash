import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:menval/app/motion.dart';

/// A reusable, gesture-passive plastic press effect.
///
/// It listens to pointers rather than owning the tap recognizer, so existing
/// InkWell, IconButton, long-press, keyboard and accessibility actions continue
/// to work. Dragging a scrollable child cancels the pressed appearance.
class PressDepth extends StatefulWidget {
  const PressDepth({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.enabled = true,
    this.scale = 0.975,
    this.shadows = false,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final bool enabled;
  final double scale;

  /// Adds a subtle lifted idle shadow; leave off on already elevated cards.
  final bool shadows;

  @override
  State<PressDepth> createState() => _PressDepthState();
}

class _PressDepthState extends State<PressDepth> {
  int? _pointer;
  Offset? _origin;
  bool _pressed = false;

  void _down(PointerDownEvent event) {
    if (!mounted || !widget.enabled || _pointer != null) return;
    if (event.kind == PointerDeviceKind.mouse && event.buttons != 1) return;
    _pointer = event.pointer;
    _origin = event.position;
    setState(() => _pressed = true);
  }

  void _move(PointerMoveEvent event) {
    if (_pointer != event.pointer || _origin == null) return;
    if ((event.position - _origin!).distance > 16) {
      _release(event.pointer);
    }
  }

  void _release(int pointer) {
    if (_pointer != pointer) return;
    _pointer = null;
    _origin = null;
    if (mounted && _pressed) setState(() => _pressed = false);
  }

  @override
  void didUpdateWidget(covariant PressDepth oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) {
      _pointer = null;
      _origin = null;
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final duration = Motion.of(
      context,
      _pressed
          ? const Duration(milliseconds: 85)
          : const Duration(milliseconds: 190),
    );
    final shade = colors.shadow.withValues(alpha: isDark ? 0.17 : 0.12);
    final highlight = Colors.white.withValues(alpha: isDark ? 0.05 : 0.15);

    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: (event) => _release(event.pointer),
      onPointerCancel: (event) => _release(event.pointer),
      child: AnimatedScale(
        scale: widget.enabled && _pressed ? widget.scale : 1,
        alignment: Alignment.center,
        curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
        duration: duration,
        child: AnimatedSlide(
          offset: widget.enabled && _pressed
              ? const Offset(0, 0.025)
              : Offset.zero,
          duration: duration,
          curve: Motion.enter,
          child: AnimatedContainer(
            duration: duration,
            curve: Motion.enter,
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              boxShadow: !widget.shadows || _pressed
                  ? const []
                  : [
                      BoxShadow(
                        color: shade,
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              gradient: !_pressed || !widget.enabled
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        shade.withValues(alpha: isDark ? 0.30 : 0.45),
                        Colors.transparent,
                        highlight,
                      ],
                      stops: const [0, 0.55, 1],
                    ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
