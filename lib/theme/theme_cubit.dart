import 'dart:ui' show PlatformDispatcher;

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../components/core/app_colors.dart';
import '../components/core/app_text.dart';

/// The chosen appearance and whether it currently resolves to light.
class ThemeState extends Equatable {
  const ThemeState(this.mode, this.light);

  /// What the player picked: system, light or dark.
  final ThemeMode mode;

  /// What is actually on screen right now.
  final bool light;

  @override
  List<Object?> get props => [mode, light];
}

/// Owns light/dark. The choice is saved on the device so it applies on the
/// sign in screen too, and "System" follows the phone live.
///
/// ```dart
/// context.read<ThemeCubit>().setMode(ThemeMode.light);
/// ```
class ThemeCubit extends Cubit<ThemeState> with WidgetsBindingObserver {
  ThemeCubit._(this._prefs, ThemeMode mode) : super(ThemeState(mode, _resolve(mode))) {
    AppColors.light = state.light;
    WidgetsBinding.instance.addObserver(this);
  }

  static const _key = 'theme_mode';
  final SharedPreferences? _prefs;

  /// Reads the saved choice. Call once in `main()` before `runApp` so the first frame is right.
  static Future<ThemeCubit> load() async {
    SharedPreferences? prefs;
    var mode = ThemeMode.dark;
    try {
      prefs = await SharedPreferences.getInstance();
      mode = switch (prefs.getString(_key)) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };
    } catch (_) {
      // Storage unavailable: run with the default and don't persist.
    }
    return ThemeCubit._(prefs, mode);
  }

  static bool _resolve(ThemeMode mode) => switch (mode) {
        ThemeMode.light => true,
        ThemeMode.dark => false,
        ThemeMode.system => PlatformDispatcher.instance.platformBrightness == Brightness.light,
      };

  Future<void> setMode(ThemeMode mode) async {
    _apply(mode);
    try {
      await _prefs?.setString(_key, mode.name);
    } catch (_) {}
  }

  @override
  void didChangePlatformBrightness() {
    if (state.mode == ThemeMode.system) _apply(ThemeMode.system);
  }

  void _apply(ThemeMode mode) {
    final light = _resolve(mode);
    final changed = light != AppColors.light;
    AppColors.light = light;
    // Colours are read straight from AppColors, so every widget has to build
    // again, including const ones that Flutter would otherwise skip.
    if (changed) _repaintAll();
    emit(ThemeState(mode, light));
  }

  static void _repaintAll() {
    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
  }

  @override
  Future<void> close() {
    WidgetsBinding.instance.removeObserver(this);
    return super.close();
  }
}

/// Material theme that matches [AppColors] and uses Space Grotesk everywhere.
ThemeData buildAppTheme() {
  final light = AppColors.light;
  final brightness = light ? Brightness.light : Brightness.dark;
  final base = ThemeData(brightness: brightness, useMaterial3: true);
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFFFC83D), brightness: brightness).copyWith(
    surface: AppColors.surface,
    onSurface: AppColors.text,
    primary: AppColors.gold,
    onPrimary: AppColors.onAccent,
    error: AppColors.loss,
    outline: AppColors.lineStrong,
    outlineVariant: AppColors.line,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    canvasColor: AppColors.bg,
    dividerColor: AppColors.line,
    textTheme: base.textTheme.apply(fontFamily: AppText.family, bodyColor: AppColors.text, displayColor: AppColors.text),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: AppText.family),
    splashFactory: NoSplash.splashFactory,
    bottomSheetTheme: const BottomSheetThemeData(constraints: BoxConstraints(maxWidth: 600)),
  );
}
