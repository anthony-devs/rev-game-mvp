import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/app_tokens.dart';
import '../core/press_scale.dart';

enum AppButtonVariant {
  /// White fill. Default call to action.
  primary,

  /// Green fill with a 3D lip. Spin, Bet, Roll, Deal.
  success,

  /// Gold fill with a 3D lip. Claim, Cash out, Continue.
  gold,

  /// Transparent with a border. Secondary action.
  outline,

  /// Dark surface fill. Quiet action.
  ghost,

  /// Red tint. Destructive action.
  danger,
}

/// The main button of the app.
///
/// ```dart
/// AppButton(label: 'Play now', variant: AppButtonVariant.success, onPressed: () {})
/// AppButton(label: 'SPIN', sublabel: 'BET 100.00', variant: AppButtonVariant.success, height: 68, onPressed: spin)
/// AppButton(label: 'Sign in', onPressed: null) // disabled
/// ```
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.sublabel,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.height = 56,
    this.expanded = true,
    this.loading = false,
    this.fontSize = 16,
    this.letterSpacing,
    this.radius = AppRadius.lg,
    this.haptic = true,
  });

  final String label;

  /// Small line under the label (e.g. `BET 100.00`).
  final String? sublabel;

  /// `null` shows the disabled style.
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final double height;

  /// `true` fills the available width, `false` hugs the content.
  final bool expanded;
  final bool loading;
  final double fontSize;
  final double? letterSpacing;
  final double radius;
  final bool haptic;

  bool get _disabled => onPressed == null || loading;

  @override
  Widget build(BuildContext context) {
    final s = _style();
    final fg = _disabled && variant != AppButtonVariant.outline && variant != AppButtonVariant.ghost
        ? AppColors.textDim
        : s.fg;

    Widget content;
    if (loading) {
      content = SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
      );
    } else if (sublabel != null) {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: AppText.body(fontSize, weight: FontWeight.w800, color: fg, letterSpacing: letterSpacing ?? 2, height: 1.1)),
          const SizedBox(height: 3),
          Text(sublabel!,
              style: AppText.body(11, weight: FontWeight.w700, color: fg.withValues(alpha: .72), letterSpacing: 1, height: 1)),
        ],
      );
    } else {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 20, color: fg), const SizedBox(width: 8)],
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(fontSize, weight: FontWeight.w700, color: fg, letterSpacing: letterSpacing)),
          ),
        ],
      );
    }

    final box = Container(
      height: height,
      width: expanded ? double.infinity : null,
      padding: expanded ? null : const EdgeInsets.symmetric(horizontal: 22),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _disabled && s.bg != Colors.transparent ? AppColors.handle.withValues(alpha: .55) : s.bg,
        borderRadius: BorderRadius.circular(radius),
        border: s.border == null ? null : Border.all(color: s.border!),
        boxShadow: _disabled ? null : s.shadows,
      ),
      child: content,
    );

    return Semantics(
      button: true,
      enabled: !_disabled,
      label: label,
      child: PressScale(onTap: _disabled ? null : onPressed, haptic: haptic, child: box),
    );
  }

  _Style _style() {
    switch (variant) {
      case AppButtonVariant.primary:
        return const _Style(bg: Colors.white, fg: AppColors.bg);
      case AppButtonVariant.success:
        return _Style(
          bg: AppColors.green,
          fg: Colors.black,
          shadows: [...AppShadows.glow(AppColors.green), ...AppShadows.lip(AppColors.greenDark)],
        );
      case AppButtonVariant.gold:
        return _Style(
          bg: AppColors.gold,
          fg: AppColors.bg,
          shadows: [...AppShadows.glow(AppColors.gold), ...AppShadows.lip(AppColors.goldDark)],
        );
      case AppButtonVariant.outline:
        return const _Style(bg: Colors.transparent, fg: Colors.white, border: AppColors.lineStrong);
      case AppButtonVariant.ghost:
        return const _Style(bg: AppColors.surfaceAlt, fg: Colors.white, border: AppColors.line);
      case AppButtonVariant.danger:
        return _Style(
          bg: AppColors.lossStrong.withValues(alpha: .14),
          fg: AppColors.loss,
          border: AppColors.lossStrong.withValues(alpha: .5),
        );
    }
  }
}

class _Style {
  const _Style({required this.bg, required this.fg, this.border, this.shadows});
  final Color bg;
  final Color fg;
  final Color? border;
  final List<BoxShadow>? shadows;
}
