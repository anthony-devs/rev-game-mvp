import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Screen background. Flat on purpose: the app is calm and uncluttered, so the
/// old coloured glow is gone. [glowColor], [glowOpacity], [center] and [radius]
/// are still accepted so existing call sites keep compiling, but they do nothing.
class GlowBackground extends StatelessWidget {
  const GlowBackground({
    super.key,
    required this.child,
    this.glowColor,
    this.glowOpacity = 0,
    this.center = Alignment.center,
    this.radius = 1,
  });

  final Widget child;

  final Color? glowColor;
  final double glowOpacity;
  final Alignment center;
  final double radius;

  @override
  Widget build(BuildContext context) => ColoredBox(color: AppColors.bg, child: child);
}
