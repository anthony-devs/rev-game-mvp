import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'glow_background.dart';

/// Standard screen shell: flat themed background, status bar icons that match
/// the theme, optional floating bottom bar.
///
/// ```dart
/// AppScaffold(
///   glowColor: AppColors.purple,
///   bottomBar: AppTabBar(...),
///   body: ListView(...),
/// )
/// ```
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.body,
    this.bottomBar,
    this.glowColor,
    this.safeTop = true,
    this.padding = EdgeInsets.zero,
    this.maxWidth = 720,
  });

  final Widget body;

  /// Floating widget pinned to the bottom (e.g. `AppTabBar`).
  final Widget? bottomBar;
  final Color? glowColor;
  final bool safeTop;
  final EdgeInsets padding;

  /// Content never grows wider than this (iPad, Mac, browser). Phones are narrower, so nothing changes.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppColors.light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: GlowBackground(
          glowColor: glowColor,
          child: SafeArea(
            top: safeTop,
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Stack(
                  children: [
                    Positioned.fill(child: Padding(padding: padding, child: body)),
                    if (bottomBar != null)
                      Positioned(
                        left: math.max(24, (MediaQuery.sizeOf(context).width - 560) / 2),
                        right: math.max(24, (MediaQuery.sizeOf(context).width - 560) / 2),
                        bottom: MediaQuery.of(context).padding.bottom + 8,
                        child: bottomBar!,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
