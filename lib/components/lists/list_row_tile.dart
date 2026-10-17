import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/press_scale.dart';

/// Settings-style row: icon, title, subtitle, trailing value/chevron.
///
/// ```dart
/// ListRowTile(icon: Icons.shield_outlined, title: 'Limits', subtitle: 'Session and spend', onTap: openLimits)
/// ListRowTile(title: 'Version', trailingText: '1.0.0')
/// ```
class ListRowTile extends StatelessWidget {
  const ListRowTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.trailingText,
    this.trailing,
    this.onTap,
    this.showChevron = true,
    this.titleColor,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final String? trailingText;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scale: .99,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            if (icon != null) ...[Icon(icon, size: 22, color: (iconColor ?? AppColors.textMuted)), const SizedBox(width: 14)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.body(15, weight: FontWeight.w600, color: (titleColor ?? AppColors.text))),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: AppText.body(12, color: AppColors.textDim)),
                  ],
                ],
              ),
            ),
            if (trailingText != null) Text(trailingText!, style: AppText.body(14, color: AppColors.textDim)),
            if (trailing != null) trailing!,
            if (onTap != null && showChevron && trailing == null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 22, color: AppColors.textFaint),
            ],
          ],
        ),
      ),
    );
  }
}
