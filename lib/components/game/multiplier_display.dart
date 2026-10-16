import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/formatters.dart';

/// Huge glowing multiplier / result number.
///
/// ```dart
/// MultiplierDisplay(value: 2.31)
/// MultiplierDisplay(value: 1.00, color: AppColors.loss, caption: 'BUSTED')
/// ```
class MultiplierDisplay extends StatelessWidget {
  const MultiplierDisplay({super.key, required this.value, this.color = AppColors.green, this.caption, this.size = 56});

  final double value;
  final Color color;
  final String? caption;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(formatMultiplier(value), style: AppText.number(size, color: color, shadows: AppText.glow(color))),
        if (caption != null) ...[const SizedBox(height: 4), Text(caption!, style: AppText.label(color: color))],
      ],
    );
  }
}
