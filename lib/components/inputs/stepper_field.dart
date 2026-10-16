import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/app_tokens.dart';
import '../core/press_scale.dart';

/// Label + value box with minus and plus buttons and an optional on/off switch.
/// Used for Auto cash out, Rows, Target, Number of rounds.
///
/// ```dart
/// StepperField(
///   label: 'Auto cash out',
///   valueText: '2.00x',
///   active: autoOn, onToggle: (v) => setState(() => autoOn = v),
///   onMinus: () => setTarget(t - .1), onPlus: () => setTarget(t + .1),
/// )
/// ```
class StepperField extends StatelessWidget {
  const StepperField({
    super.key,
    required this.label,
    required this.valueText,
    required this.onMinus,
    required this.onPlus,
    this.active = true,
    this.onToggle,
  });

  final String label;
  final String valueText;

  /// `null` disables the button.
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  /// Dims the value when `false`. Pair with [onToggle].
  final bool active;

  /// When set, a small switch is shown and the stepper buttons only work while [active].
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    final live = onToggle == null || active;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label.toUpperCase(), style: AppText.label())),
            if (onToggle != null)
              SizedBox(
                height: 20,
                child: FittedBox(
                  child: Switch(
                    value: active,
                    onChanged: onToggle,
                    activeColor: Colors.black,
                    activeTrackColor: AppColors.green,
                    inactiveThumbColor: AppColors.textDim,
                    inactiveTrackColor: AppColors.track,
                    trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              _Btn(icon: Icons.remove_rounded, onTap: live ? onMinus : null),
              Expanded(
                child: Center(
                  child: Text(valueText, style: AppText.number(18, color: live ? AppColors.gold : AppColors.textFaint)),
                ),
              ),
              _Btn(icon: Icons.add_rounded, onTap: live ? onPlus : null),
            ],
          ),
        ),
      ],
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: AppColors.handle.withValues(alpha: onTap == null ? .3 : 1), borderRadius: BorderRadius.circular(AppRadius.sm)),
        child: Icon(icon, size: 20, color: onTap == null ? AppColors.textFaint : AppColors.text),
      ),
    );
  }
}
