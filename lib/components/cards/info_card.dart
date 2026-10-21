import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';

/// Tinted note card: demo disclaimers, tips, warnings.
///
/// ```dart
/// InfoCard(message: 'Coins have no cash value.')
/// InfoCard(title: 'Heads up', message: 'Daily limit reached.', color: AppColors.gold, icon: Icons.warning_amber_rounded)
/// ```
class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.message,
    this.title,
    this.icon = Icons.info_outline_rounded,
    this.color,
  });

  final String? title;
  final String message;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (color ?? AppColors.blue).withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: (color ?? AppColors.blue).withValues(alpha: .3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: (color ?? AppColors.blue)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) Text(title!, style: AppText.body(14, weight: FontWeight.w700)),
                Text(message, style: AppText.body(13, color: AppColors.textMuted, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
