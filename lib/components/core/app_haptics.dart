import 'package:flutter/services.dart';

/// Haptic feedback that respects the player's "Haptics" setting.
/// Use this instead of calling HapticFeedback directly.
///
/// ```dart
/// AppHaptics.light();
/// ```
class AppHaptics {
  AppHaptics._();

  /// Kept in sync with the player's settings by ProfileCubit.
  static bool enabled = true;

  static void light() {
    if (enabled) HapticFeedback.lightImpact();
  }

  static void medium() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  static void heavy() {
    if (enabled) HapticFeedback.heavyImpact();
  }

  static void selection() {
    if (enabled) HapticFeedback.selectionClick();
  }
}
