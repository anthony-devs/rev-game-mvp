import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/app_tokens.dart';
import '../core/formatters.dart';
import '../core/press_scale.dart';

/// Bet amount box with 1/2 and 2x shortcuts. Controlled: the parent owns [value].
///
/// ```dart
/// AmountField(
///   label: 'Bet amount',
///   value: bet,
///   min: 10, max: balance,
///   onChanged: (v) => setState(() => bet = v),
/// )
/// ```
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Bet amount',
    this.min = 0,
    this.max,
    this.enabled = true,
    this.showShortcuts = true,
    this.decimals = 2,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final String label;
  final double min;
  final double? max;
  final bool enabled;
  final bool showShortcuts;
  final int decimals;

  double _clamp(double v) {
    var r = v < min ? min : v;
    if (max != null && r > max!) r = max!;
    return r;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppText.label()),
        const SizedBox(height: 8),
        Opacity(
          opacity: enabled ? 1 : .5,
          child: Container(
            height: 56,
            padding: const EdgeInsets.only(left: 16, right: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(formatCredits(value, decimals: decimals), style: AppText.number(20)),
                  ),
                ),
                if (showShortcuts) ...[
                  _Chip(label: '1/2', onTap: enabled ? () => onChanged(_clamp(value / 2)) : null),
                  const SizedBox(width: 6),
                  _Chip(label: '2x', onTap: enabled ? () => onChanged(_clamp(value * 2)) : null),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.handle,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(label, style: AppText.body(14, weight: FontWeight.w800)),
      ),
    );
  }
}
