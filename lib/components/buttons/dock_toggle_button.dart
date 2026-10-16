import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/press_scale.dart';

/// Icon + caption toggle that sits beside the main action: TURBO, AUTO.
///
/// ```dart
/// DockToggleButton(icon: Icons.bolt_rounded, label: 'TURBO', active: turbo, onPressed: () => setState(() => turbo = !turbo))
/// ```
class DockToggleButton extends StatelessWidget {
  const DockToggleButton({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onPressed,
    this.width = 60,
    this.height = 68,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onPressed;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = active ? AppColors.gold : AppColors.textSoft;
    return PressScale(
      onTap: onPressed,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: active ? AppColors.gold.withValues(alpha: .12) : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? AppColors.gold : AppColors.line),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: c),
            const SizedBox(height: 5),
            Text(label, style: AppText.body(10, weight: FontWeight.w800, color: c, letterSpacing: 1, height: 1)),
          ],
        ),
      ),
    );
  }
}
