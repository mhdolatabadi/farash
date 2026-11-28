import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:menval/app/design_tokens.dart';
import 'package:menval/app/motion.dart';
import 'package:menval/app/palette.dart';

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
    this.statesController,
    this.inset = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final bool enabled;
  final double scale;

  /// Adds a subtle lifted idle shadow; leave off on already elevated cards.
  final bool shadows;

  /// Supplies keyboard activation as well as pointer activation from a button.
  final WidgetStatesController? statesController;

  /// A compact checkbox paints its inset on the mark instead of the hit area.
  final bool inset;

  @override
  State<PressDepth> createState() => _PressDepthState();
}

class _PressDepthState extends State<PressDepth> {
  int? _pointer;
  Offset? _origin;
  bool _pressed = false;

  bool get _active =>
      widget.enabled &&
      (_pressed ||
          (widget.statesController?.value.contains(WidgetState.pressed) ??
              false));

  @override
  void initState() {
    super.initState();
    widget.statesController?.addListener(_statesChanged);
  }

  void _statesChanged() {
    if (mounted) setState(() {});
  }

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
    if (oldWidget.statesController != widget.statesController) {
      oldWidget.statesController?.removeListener(_statesChanged);
      widget.statesController?.addListener(_statesChanged);
    }
    if (!widget.enabled && oldWidget.enabled) {
      _pointer = null;
      _origin = null;
      _pressed = false;
    }
  }

  @override
  void dispose() {
    widget.statesController?.removeListener(_statesChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = MenvalPaletteColors.of(context);
    final duration = Motion.of(context, MenvalDesignTokens.motion);
    final active = _active;

    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: (event) => _release(event.pointer),
      onPointerCancel: (event) => _release(event.pointer),
      child: AnimatedScale(
        scale: active ? widget.scale : 1,
        alignment: Alignment.center,
        curve: Motion.enter,
        duration: duration,
        child: AnimatedSlide(
          offset: active ? const Offset(0, 0.02) : Offset.zero,
          duration: duration,
          curve: Motion.enter,
          child: AnimatedContainer(
            duration: duration,
            curve: Motion.enter,
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              boxShadow: !widget.enabled || !widget.shadows || active
                  ? const []
                  : [
                      BoxShadow(
                        color: palette.softShade,
                        blurRadius: 8,
                        offset: const Offset(3, 4),
                      ),
                      BoxShadow(
                        color: palette.softLight,
                        blurRadius: 8,
                        offset: const Offset(-3, -3),
                      ),
                    ],
            ),
            child: CustomPaint(
              foregroundPainter: active && widget.inset
                  ? MenvalInsetPainter(
                      light: palette.softLight,
                      shade: palette.softShade,
                      borderRadius: widget.borderRadius,
                    )
                  : null,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared inner-shadow paint for wells and pressed controls. The shadow stays
/// inside the shape, so it never obscures adjacent controls or enlarges layout.
class MenvalInsetPainter extends CustomPainter {
  const MenvalInsetPainter({
    required this.light,
    required this.shade,
    this.borderRadius = MenvalDesignTokens.radius,
    this.circle = false,
    this.edge,
  });

  final Color light;
  final Color shade;
  final BorderRadius borderRadius;
  final bool circle;
  final Color? edge;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = circle
        ? (Path()..addOval(rect))
        : (Path()..addRRect(borderRadius.toRRect(rect)));
    canvas.save();
    canvas.clipPath(shape);
    void cast(Color color, Offset offset) {
      final outside = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect.inflate(24))
        ..addPath(shape, Offset.zero);
      canvas.drawPath(
        outside.shift(offset),
        Paint()
          ..color = color
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
      );
    }

    cast(shade, const Offset(3, 3));
    cast(light, const Offset(-3, -3));
    canvas.restore();
    if (edge case final edgeColor?) {
      canvas.drawPath(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = edgeColor,
      );
    }
  }

  @override
  bool shouldRepaint(MenvalInsetPainter old) =>
      old.light != light ||
      old.shade != shade ||
      old.borderRadius != borderRadius ||
      old.circle != circle ||
      old.edge != edge;
}
