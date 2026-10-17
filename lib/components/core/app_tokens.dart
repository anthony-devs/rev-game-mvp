import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Spacing, radii and shared shadows.
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  /// Horizontal screen padding used across the app.
  static const double screen = 16;
}

class AppRadius {
  AppRadius._();
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double pill = 999;
}

class AppShadows {
  AppShadows._();

  /// Flat buttons: the old bottom lip is gone. Kept so call sites still compile.
  static List<BoxShadow> lip(Color color) => const [];

  /// Flat design: no coloured glow. Kept so call sites still compile.
  static List<BoxShadow> glow(Color color, {double blur = 24, double opacity = .3}) => const [];

  /// Soft lift for floating bars.
  static List<BoxShadow> get card => [
        BoxShadow(color: Color(AppColors.light ? 0x1A000000 : 0x80000000), blurRadius: 20, offset: const Offset(0, 8)),
      ];
}
