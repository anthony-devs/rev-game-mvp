import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/press_scale.dart';

/// Small rounded outline button: Undo, Clear, Paytable, Find support.
///
/// ```dart
/// PillButton(label: 'Paytable', icon: Icons.format_list_bulleted_rounded, onPressed: openPaytable)
/// ```
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 40,
    this.fontSize = 13,
    this.color,
    this.borderColor,
    this.horizontalPadding = 16,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final double fontSize;
  final Color? color;
  final Color? borderColor;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final c = onPressed == null ? AppColors.textFaint : (color ?? AppColors.text);
    return PressScale(
      cooldown: const Duration(milliseconds: 700),
      onTap: onPressed,
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height),
          border: Border.all(color: (borderColor ?? AppColors.lineStrong)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 18, color: c), const SizedBox(width: 8)],
            Text(label, style: AppText.body(fontSize, weight: FontWeight.w700, color: c)),
          ],
        ),
      ),
    );
  }
}
