import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'glow_background.dart';

/// Standard screen shell: dark background, status bar icons set to light,
/// optional glow, optional floating bottom bar.
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
  });

  final Widget body;

  /// Floating widget pinned to the bottom (e.g. `AppTabBar`).
  final Widget? bottomBar;
  final Color? glowColor;
  final bool safeTop;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: GlowBackground(
          glowColor: glowColor,
          child: SafeArea(
            top: safeTop,
            bottom: false,
            child: Stack(
              children: [
                Padding(padding: padding, child: body),
                if (bottomBar != null)
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: MediaQuery.of(context).padding.bottom + 8,
                    child: bottomBar!,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
