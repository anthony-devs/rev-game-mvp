import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/press_scale.dart';

/// Section title with optional leading icon and trailing action link.
///
/// ```dart
/// SectionHeader(title: 'Popular', actionLabel: 'See all', onAction: openBrowse)
/// ```
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.iconColor = AppColors.gold,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final String title;
  final IconData? icon;
  final Color iconColor;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 20, color: iconColor), const SizedBox(width: 8)],
          Expanded(child: Text(title, style: AppText.body(18, weight: FontWeight.w700, letterSpacing: -.2))),
          if (actionLabel != null)
            PressScale(
              onTap: onAction,
              child: Text(actionLabel!, style: AppText.body(13, weight: FontWeight.w600, color: AppColors.textMuted)),
            ),
        ],
      ),
    );
  }
}
