import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Text styles. Space Grotesk for everything; JetBrains Mono for seeds and hashes.
/// Both fonts ship inside the app.
class AppText {
  AppText._();

  /// Bundled in assets/fonts (no download, works offline, no first-use flicker).
  static const String family = 'SpaceGrotesk';
  static const String monoFamily = 'JetBrainsMono';

  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  /// Regular UI text.
  static TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color? color,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
    bool tabularFigures = false,
  }) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.text,
        letterSpacing: letterSpacing,
        height: height,
        decoration: decoration,
        fontFeatures: tabularFigures ? tabular : null,
      );

  /// Bold headings.
  static TextStyle heading(
    double size, {
    Color? color,
    double letterSpacing = -0.6,
    double? height = 1.1,
  }) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: FontWeight.w800,
        color: color ?? AppColors.text,
        letterSpacing: letterSpacing,
        height: height,
      );

  /// Small uppercase section label, e.g. "GAMEPLAY".
  static TextStyle label({Color? color, double size = 11}) => TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.textDim,
        letterSpacing: 1.4,
      );

  /// Digital counters: balances, multipliers, big win amounts.
  static TextStyle number(
    double size, {
    Color? color,
    FontWeight weight = FontWeight.w800,
    List<Shadow>? shadows,
  }) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: weight,
        color: color ?? AppColors.text,
        height: 1.1,
        shadows: shadows,
        fontFeatures: tabular,
      );

  /// Seeds, hashes, ids.
  static TextStyle mono(double size, {Color? color}) =>
      TextStyle(fontFamily: monoFamily, fontSize: size, fontWeight: FontWeight.w500, color: color ?? AppColors.textSoft);

  /// Kept so existing call sites compile. The app is flat and calm now, so there is no glow.
  static List<Shadow> glow(Color color, {double blur = 18, double opacity = .6}) => const [];
}
