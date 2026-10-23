import 'package:flutter/material.dart';

/// Colour tokens for the REV GAMES design language, in dark and light.
///
/// Every token is a getter that follows [AppColors.light]. [ThemeCubit] flips
/// it and repaints the app, so widgets just read `AppColors.surface` and never
/// check the mode themselves. Because the values change at runtime they can't
/// be used inside `const` expressions.
class AppColors {
  AppColors._();

  /// True while the light theme is active. Set only by `ThemeCubit`.
  static bool light = false;
  static Brightness get brightness => light ? Brightness.light : Brightness.dark;

  static Color _p(Color dark, Color lightValue) => light ? lightValue : dark;

  // Surfaces
  static Color get bg => _p(const Color(0xFF0B0B0C), const Color(0xFFF5F5F6));
  static Color get surface => _p(const Color(0xFF161618), const Color(0xFFFFFFFF));
  static Color get surfaceAlt => _p(const Color(0xFF1C1C1E), const Color(0xFFF7F7F8));
  static Color get surfaceRaised => _p(const Color(0xFF1E1E20), const Color(0xFFFFFFFF));
  static Color get sheet => _p(const Color(0xFF131316), const Color(0xFFFFFFFF));
  static Color get track => _p(const Color(0xFF2A2A2E), const Color(0xFFE8E8EC));
  static Color get handle => _p(const Color(0xFF3A3A40), const Color(0xFFC6C6CC));

  // Lines
  static Color get line => _p(const Color(0x14FFFFFF), const Color(0x12000000));
  static Color get lineStrong => _p(const Color(0x33FFFFFF), const Color(0x1F000000));

  // Text
  static Color get text => _p(const Color(0xFFFFFFFF), const Color(0xFF111113));
  static Color get textSoft => _p(const Color(0xFFD1D1D6), const Color(0xFF3A3A40));
  static Color get textMuted => _p(const Color(0xFFAEAEB2), const Color(0xFF6B6B73));
  static Color get textDim => _p(const Color(0xFF8E8E93), const Color(0xFF86868E));
  static Color get textFaint => _p(const Color(0xFF85858B), const Color(0xFF6A6A72));

  /// Fill for high-contrast controls (selected chip, primary button): white on dark, ink on light.
  static Color get inverse => _p(const Color(0xFFFFFFFF), const Color(0xFF1C1D20));

  /// Text and icons that sit on [inverse].
  static Color get onInverse => _p(const Color(0xFF0B0B0C), const Color(0xFFFFFFFF));

  /// Text and icons that sit on a brand colour (gold, green, purple...).
  static Color get onAccent => _p(const Color(0xFF0B0B0C), const Color(0xFFFFFFFF));

  // Brand + status. Slightly deeper in light mode so they stay readable on white.
  static Color get gold => _p(const Color(0xFFFFC83D), const Color(0xFF8F6000));
  static Color get goldSoft => _p(const Color(0xFFFFD36B), const Color(0xFFCB9200));
  static Color get goldDark => _p(const Color(0xFFB8860B), const Color(0xFF8A5E00));
  static Color get green => _p(const Color(0xFF2EE59D), const Color(0xFF16883E));
  static Color get greenDark => _p(const Color(0xFF17A872), const Color(0xFF087A52));
  static Color get mint => _p(const Color(0xFF5DF2B5), const Color(0xFF14B382));
  /// The selection / highlight colour. Named purple from before; it is an indigo blue now.
  static Color get purple => _p(const Color(0xFF7C8CFF), const Color(0xFF4F5BD5));
  static Color get purpleDeep => _p(const Color(0xFF4B58D6), const Color(0xFF3844B8));
  static Color get loss => _p(const Color(0xFFFF6B6D), const Color(0xFFC42A37));
  static Color get lossStrong => _p(const Color(0xFFFF4D4F), const Color(0xFFC62833));
  static Color get blue => _p(const Color(0xFF2E9BFF), const Color(0xFF1B6BD6));

  /// Colour at a given opacity, e.g. `AppColors.tint(AppColors.gold, .14)`.
  static Color tint(Color c, double opacity) => c.withValues(alpha: opacity);
}
