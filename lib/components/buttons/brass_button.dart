import 'package:flutter/material.dart';

import '../core/app_text.dart';
import '../core/press_scale.dart';

/// Brass key button for bet controls on the slot machine panel: MIN, 1/2, 2x, MAX, + and - keys.
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

  static const Color _ink = Color(0xFF2A1A05);

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
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF6CE7A), Color(0xFFC98F33)],
              ),
              boxShadow: const [BoxShadow(color: Color(0xFF7A5214), offset: Offset(0, 3))],
            ),
            child: icon != null
                ? Icon(icon, size: 20, color: _ink)
                : Text(label!, style: AppText.body(fontSize, weight: FontWeight.w800, color: _ink)),
          ),
        ),
      ),
    );
  }
}
