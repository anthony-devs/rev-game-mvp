import 'package:flutter/material.dart';

/// Colour tokens for the REV GAMES design language.
/// Change a value here and every component updates.
class AppColors {
  AppColors._();

  // Surfaces
  static const Color bg = Color(0xFF0B0B0C);
  static const Color surface = Color(0xFF161618);
  static const Color surfaceAlt = Color(0xFF1C1C1E);
  static const Color surfaceRaised = Color(0xFF1E1E20);
  static const Color sheet = Color(0xFF131316);
  static const Color track = Color(0xFF2A2A2E);
  static const Color handle = Color(0xFF3A3A40);

  // Lines
  static const Color line = Color(0x14FFFFFF); // white 8%
  static const Color lineStrong = Color(0x33FFFFFF); // white 20%

  // Text
  static const Color text = Color(0xFFFFFFFF);
  static const Color textSoft = Color(0xFFD1D1D6);
  static const Color textMuted = Color(0xFFAEAEB2);
  static const Color textDim = Color(0xFF8E8E93);
  static const Color textFaint = Color(0xFF6E6E73);

  // Brand + status
  static const Color gold = Color(0xFFFFC83D);
  static const Color goldSoft = Color(0xFFFFD36B);
  static const Color goldDark = Color(0xFFB8860B);
  static const Color green = Color(0xFF2EE59D);
  static const Color greenDark = Color(0xFF17A872);
  static const Color mint = Color(0xFF5DF2B5);
  static const Color purple = Color(0xFFB26BFF);
  static const Color purpleDeep = Color(0xFF7A2FD0);
  static const Color loss = Color(0xFFFF6B6D);
  static const Color lossStrong = Color(0xFFFF4D4F);
  static const Color blue = Color(0xFF2E9BFF);

  /// Colour at a given opacity, e.g. `AppColors.tint(AppColors.gold, .14)`.
  static Color tint(Color c, double opacity) => c.withValues(alpha: opacity);
}
