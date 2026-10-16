import 'package:flutter/material.dart';

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

  /// Bottom-lip "3D" shadow under chunky buttons.
  static List<BoxShadow> lip(Color color) => [BoxShadow(color: color, offset: const Offset(0, 4))];

  /// Coloured glow.
  static List<BoxShadow> glow(Color color, {double blur = 24, double opacity = .3}) =>
      [BoxShadow(color: color.withValues(alpha: opacity), blurRadius: blur)];

  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x80000000), blurRadius: 20, offset: Offset(0, 8)),
  ];
}
