import 'package:flutter/material.dart';

import '../core/app_colors.dart';

/// Rounded progress bar. [value] is 0.0 to 1.0.
///
/// ```dart
/// AppProgressBar(value: xp / xpMax)
/// AppProgressBar(value: .4, color: AppColors.green, height: 6)
/// ```
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    super.key,
    required this.value,
    this.color = AppColors.purple,
    this.trackColor = AppColors.track,
    this.height = 8,
  });

  final double value;
  final Color color;
  final Color trackColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: trackColor,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(height),
              gradient: LinearGradient(colors: [color.withValues(alpha: .75), color]),
            ),
          ),
        ),
      ),
    );
  }
}
