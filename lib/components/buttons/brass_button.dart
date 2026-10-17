import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/press_scale.dart';

/// Gold key button for bet controls on the slot machine panel: MIN, 1/2, 2x, MAX, + and - keys.
///
/// ```dart
/// BrassButton(label: 'MAX', onPressed: () => setBet(max))
/// BrassButton(icon: Icons.add_rounded, width: 44, semanticLabel: 'Increase bet', onPressed: inc)
/// ```
class BrassButton extends StatelessWidget {
  const BrassButton({
    super.key,
    required this.onPressed,
    this.label,
    this.icon,
    this.semanticLabel,
    this.width = 52,
    this.height = 44,
    this.fontSize = 14,
  }) : assert(label != null || icon != null, 'Give a label or an icon');

  final VoidCallback? onPressed;
  final String? label;
  final IconData? icon;
  final String? semanticLabel;
  final double width;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: PressScale(
        onTap: onPressed,
        child: Opacity(
          opacity: onPressed == null ? .45 : 1,
          child: Container(
            width: width,
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppColors.gold,
            ),
            child: icon != null
                ? Icon(icon, size: 20, color: AppColors.onAccent)
                : Text(label!, style: AppText.body(fontSize, weight: FontWeight.w800, color: AppColors.onAccent)),
          ),
        ),
      ),
    );
  }
}
