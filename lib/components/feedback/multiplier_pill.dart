import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/formatters.dart';

/// Coloured multiplier chip (crash history, win results).
/// With [color] unset the tone is picked from the value:
/// below 2x red, 2x to 10x green, 10x and up gold.
///
/// ```dart
/// MultiplierPill(value: 3.42)
/// MultiplierPill(value: 1.00, color: AppColors.loss)
/// ```
class MultiplierPill extends StatelessWidget {
  const MultiplierPill({super.key, required this.value, this.color, this.fontSize = 13, this.decimals = 2});

  final double value;
  final Color? color;
  final double fontSize;
  final int decimals;

  static Color toneFor(double v) {
    if (v < 2) return AppColors.loss;
    if (v < 10) return AppColors.green;
    return AppColors.gold;
  }

  @override
  Widget build(BuildContext context) {
    final c = color ?? toneFor(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: .5)),
      ),
      child: Text(formatMultiplier(value, decimals: decimals), style: AppText.number(fontSize, color: c, weight: FontWeight.w700)),
    );
  }
}
