import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Text styles. Poppins for UI, Orbitron for credit counters and multipliers.
class AppText {
  AppText._();

  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  /// Regular UI text.
  static TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = AppColors.text,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
    bool tabularFigures = false,
  }) =>
      GoogleFonts.poppins(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
        decoration: decoration,
        fontFeatures: tabularFigures ? tabular : null,
      );

  /// Bold headings.
  static TextStyle heading(
    double size, {
    Color color = AppColors.text,
    double letterSpacing = -0.6,
    double? height = 1.1,
  }) =>
      GoogleFonts.poppins(
        fontSize: size,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  /// Small uppercase section label, e.g. "GAMEPLAY".
  static TextStyle label({Color color = AppColors.textDim, double size = 11}) => GoogleFonts.poppins(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 1.4,
      );

  /// Digital counters: balances, multipliers, big win amounts.
  static TextStyle number(
    double size, {
    Color color = AppColors.text,
    FontWeight weight = FontWeight.w800,
    List<Shadow>? shadows,
  }) =>
      GoogleFonts.orbitron(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: 1.1,
        shadows: shadows,
        fontFeatures: tabular,
      );

  /// Seeds, hashes, ids.
  static TextStyle mono(double size, {Color color = AppColors.textSoft}) =>
      GoogleFonts.jetBrainsMono(fontSize: size, fontWeight: FontWeight.w500, color: color);

  /// Soft glow for neon-style numbers.
  static List<Shadow> glow(Color color, {double blur = 18, double opacity = .6}) =>
      [Shadow(color: color.withValues(alpha: opacity), blurRadius: blur)];
}
