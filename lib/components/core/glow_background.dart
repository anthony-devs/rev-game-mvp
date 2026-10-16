import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Dark screen background with a soft coloured glow behind the content.
///
/// ```dart
/// GlowBackground(glowColor: AppColors.purple, child: ...)
/// ```
class GlowBackground extends StatelessWidget {
  const GlowBackground({
    super.key,
    required this.child,
    this.glowColor,
    this.glowOpacity = .3,
    this.center = const Alignment(0, -0.35),
    this.radius = .9,
  });

  final Widget child;

  /// `null` for a plain dark background.
  final Color? glowColor;
  final double glowOpacity;
  final Alignment center;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.bg,
        gradient: glowColor == null
            ? null
            : RadialGradient(
                center: center,
                radius: radius,
                colors: [glowColor!.withValues(alpha: glowOpacity), glowColor!.withValues(alpha: 0)],
                stops: const [0, .7],
              ),
      ),
      child: child,
    );
  }
}
