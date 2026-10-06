import 'package:flutter/widgets.dart';

/// One motion vocabulary for the app: short, ease-out, and instant when the
/// system asks for reduced motion.
abstract final class Motion {
  /// Small state changes: a check, a chevron, a button.
  static const quick = Duration(milliseconds: 160);

  /// A row arriving or a page changing.
  static const standard = Duration(milliseconds: 280);

  /// A completed row lingering, checked, before it folds away.
  static const linger = Duration(milliseconds: 220);

  /// Decelerating ease-out for things coming in and settling.
  static const enter = Curves.easeOutCubic;

  /// Accelerating ease-in for things leaving.
  static const exit = Curves.easeInCubic;

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [duration], or zero when the system asks for reduced motion.
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}

/// A list row that grows and fades in when it arrives, and folds away when
/// it leaves, calling [onExited] once it is gone.
class RowMotion extends StatefulWidget {
  const RowMotion({
    super.key,
    required this.child,
    this.entering = false,
    this.leaving = false,
    this.onExited,
  });

  final Widget child;

  /// Animate in on first build rather than appearing at full size.
  final bool entering;

  /// Fold away; turning this off again brings the row back.
  final bool leaving;
  final VoidCallback? onExited;

  @override
  State<RowMotion> createState() => _RowMotionState();
}

class _RowMotionState extends State<RowMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.entering ? 0 : 1,
  );

  bool _exited = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = Motion.of(context, Motion.standard);
    // Leaving holds the checked row for a beat, then folds it.
    _controller.reverseDuration = Motion.of(
      context,
      Motion.linger + Motion.standard,
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.entering) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.forward();
      });
    }
    if (widget.leaving) _leave();
  }

  @override
  void didUpdateWidget(RowMotion old) {
    super.didUpdateWidget(old);
    if (widget.leaving && !old.leaving) _leave();
    if (!widget.leaving && old.leaving) {
      _exited = false;
      _controller.forward();
    }
  }

  Future<void> _leave() async {
    await _controller.reverse().orCancel.catchError((_) {});
    if (mounted && widget.leaving) _exit();
  }

  void _exit() {
    if (_exited) return;
    _exited = true;
    widget.onExited?.call();
  }

  @override
  void dispose() {
    // A row rebuilt away mid-fold still reports that it is gone.
    if (widget.leaving) _exit();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final linger =
        Motion.linger.inMicroseconds /
        (Motion.linger + Motion.standard).inMicroseconds;
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Motion.enter,
      // Reversing runs t from 1 to 0: hold full size for the linger, then
      // fold with an ease-in.
      reverseCurve: Interval(0, 1 - linger, curve: Motion.exit),
    );
    return SizeTransition(
      sizeFactor: curve,
      alignment: AlignmentDirectional.topCenter,
      child: FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.15),
            end: Offset.zero,
          ).animate(curve),
          child: widget.child,
        ),
      ),
    );
  }
}
