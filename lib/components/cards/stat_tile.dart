import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';

/// Small label + value tile for stats grids (History, Wallet).
///
/// ```dart
/// StatTile(label: 'Biggest win', value: '12,400', valueColor: AppColors.gold)
/// ```
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.valueColor, this.icon});

  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 16, color: AppColors.textDim), const SizedBox(width: 6)],
            Flexible(child: Text(label.toUpperCase(), style: AppText.label())),
          ]),
          const SizedBox(height: 8),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: AppText.number(20, color: (valueColor ?? AppColors.text)))),
        ],
      ),
    );
  }
}
