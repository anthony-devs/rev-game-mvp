import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';

/// Small outlined tag. Default text is DEMO.
///
/// ```dart
/// DemoBadge()
/// DemoBadge(label: 'NEW', color: AppColors.green)
/// ```
class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key, this.label = 'DEMO', this.color, this.fontSize = 10});

  final String label;
  final Color? color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (color ?? AppColors.gold).withValues(alpha: .12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: (color ?? AppColors.gold).withValues(alpha: .6)),
      ),
      child: Text(label, style: AppText.body(fontSize, weight: FontWeight.w800, color: (color ?? AppColors.gold), letterSpacing: 1, height: 1)),
    );
  }
}
