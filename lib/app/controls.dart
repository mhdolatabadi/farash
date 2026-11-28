import 'package:flutter/material.dart';
import 'package:menval/app/design_tokens.dart';
import 'package:menval/app/motion.dart';
import 'package:menval/app/palette.dart';
import 'package:menval/app/press_depth.dart';
import 'package:menval/app/soft.dart';

ButtonStyle _controlStyle(
  BuildContext context, {
  bool primary = false,
  bool selected = false,
}) {
  final colors = Theme.of(context).colorScheme;
  return ButtonStyle(
    fixedSize: const WidgetStatePropertyAll(
      Size.square(MenvalDesignTokens.controlHeight),
    ),
    minimumSize: const WidgetStatePropertyAll(
      Size.square(MenvalDesignTokens.controlHeight),
    ),
    maximumSize: const WidgetStatePropertyAll(
      Size.square(MenvalDesignTokens.controlHeight),
    ),
    visualDensity: VisualDensity.standard,
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    shape: const WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: MenvalDesignTokens.radius),
    ),
    animationDuration: Motion.of(context, MenvalDesignTokens.motion),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return primary ? colors.onSurface.withValues(alpha: .12) : null;
      }
      if (selected || states.contains(WidgetState.pressed)) {
        return Soft.inset(context);
      }
      return primary ? colors.primary : Colors.transparent;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return colors.onSurface.withValues(alpha: .45);
      }
      return primary && !selected && !states.contains(WidgetState.pressed)
          ? colors.onPrimary
          : colors.onSurface;
    }),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered)) {
        return colors.onSurface.withValues(alpha: .05);
      }
      return Colors.transparent;
    }),
    side: WidgetStateProperty.resolveWith((states) {
      if (!states.contains(WidgetState.disabled) &&
          states.contains(WidgetState.focused)) {
        return BorderSide(
          color: primary && !selected && !states.contains(WidgetState.pressed)
              ? colors.onPrimary
              : colors.primary,
          width: 2,
        );
      }
      return BorderSide.none;
    }),
  );
}

/// One accessible check control for tasks, subtasks, checklists and habit days.
/// The mark stays compact; its pointer/keyboard target is always 48 pixels.
class MenvalCheckbox extends StatefulWidget {
  const MenvalCheckbox({
    super.key,
    required this.value,
    required this.label,
    this.onChanged,
    this.activeColor,
    this.indeterminateIcon,
  });

  final bool value;
  final String label;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;
  final IconData? indeterminateIcon;

  @override
  State<MenvalCheckbox> createState() => _MenvalCheckboxState();
}

class _MenvalCheckboxState extends State<MenvalCheckbox> {
  final _states = WidgetStatesController();

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = MenvalPaletteColors.of(context);
    final color = widget.activeColor ?? colors.primary;
    final enabled = widget.onChanged != null;
    final onColor = widget.activeColor == null
        ? colors.onPrimary
        : ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
    void toggle() => widget.onChanged?.call(!widget.value);
    return Semantics(
      label: widget.label,
      checked: widget.value,
      enabled: enabled,
      onTap: enabled ? toggle : null,
      child: ExcludeSemantics(
        child: PressDepth(
          enabled: enabled,
          statesController: _states,
          inset: false,
          child: IconButton(
            tooltip: widget.label,
            statesController: _states,
            onPressed: enabled ? toggle : null,
            style: _controlStyle(context).copyWith(
              backgroundColor:
                  const WidgetStatePropertyAll(Colors.transparent),
            ),
            icon: Opacity(
              opacity: enabled ? 1 : .45,
              child: CustomPaint(
                foregroundPainter: widget.value
                    ? null
                    : MenvalInsetPainter(
                        light: palette.softLight,
                        shade: palette.softShade,
                        circle: true,
                      ),
                child: AnimatedContainer(
                  duration: Motion.of(context, MenvalDesignTokens.motion),
                  width: MenvalDesignTokens.checkboxSize,
                  height: MenvalDesignTokens.checkboxSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.value ? color : Soft.inset(context),
                    border: Border.all(
                      color: widget.value
                          ? color
                          : widget.activeColor ?? colors.onSurfaceVariant,
                      width: 1.5,
                    ),
                  ),
                  child: widget.value || widget.indeterminateIcon != null
                      ? Icon(
                          widget.value
                              ? Icons.check_rounded
                              : widget.indeterminateIcon,
                          size: MenvalDesignTokens.checkboxGlyph,
                          color: widget.value ? onColor : color,
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet, primary or selected action using the same control geometry.
class MenvalIconButton extends StatefulWidget {
  const MenvalIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    this.onPressed,
    this.primary = false,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool selected;

  @override
  State<MenvalIconButton> createState() => _MenvalIconButtonState();
}

class _MenvalIconButtonState extends State<MenvalIconButton> {
  final _states = WidgetStatesController();

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      tooltip: widget.tooltip,
      onPressed: widget.onPressed,
      statesController: _states,
      isSelected: widget.selected ? true : null,
      style: _controlStyle(
        context,
        primary: widget.primary,
        selected: widget.selected,
      ),
      icon: Icon(widget.icon, size: MenvalDesignTokens.iconSize),
    );
    return PressDepth(
      enabled: widget.onPressed != null,
      statesController: _states,
      shadows: widget.primary && !widget.selected,
      child: widget.selected
          ? SoftWell(
              radius: MenvalDesignTokens.controlRadius,
              padding: EdgeInsets.zero,
              child: button,
            )
          : button,
    );
  }
}
