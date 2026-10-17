import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_tokens.dart';
import '../core/press_scale.dart';

/// Square icon button: back, close, info, sound, fairness.
///
/// ```dart
/// IconSquareButton(icon: Icons.chevron_left_rounded, semanticLabel: 'Back', onPressed: () => Navigator.pop(context))
/// IconSquareButton(icon: Icons.volume_up_outlined, filled: false, semanticLabel: 'Sound', onPressed: toggle)
/// ```
class IconSquareButton extends StatelessWidget {
  const IconSquareButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.filled = true,
    this.size = 44,
    this.iconSize = 22,
    this.iconColor,
    this.badge,
    this.radius = AppRadius.md,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  /// Read by screen readers. Required because the button has no text.
  final String semanticLabel;

  /// `true` = dark filled square, `false` = icon only.
  final bool filled;
  final double size;
  final double iconSize;
  final Color? iconColor;

  /// Optional small widget pinned to the top-right corner (e.g. a dot).
  final Widget? badge;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? (filled ? AppColors.text : AppColors.textSoft);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: PressScale(
        onTap: onPressed,
        cooldown: const Duration(milliseconds: 400),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: filled ? AppColors.surfaceAlt : Colors.transparent,
                  borderRadius: BorderRadius.circular(radius),
                  border: filled ? Border.all(color: AppColors.line) : null,
                ),
                child: Icon(icon, size: iconSize, color: color),
              ),
              if (badge != null) Positioned(right: -4, top: -4, child: badge!),
            ],
          ),
        ),
      ),
    );
  }
}
