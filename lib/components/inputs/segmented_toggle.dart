import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/press_scale.dart';

/// Option for [SegmentedToggle].
class SegmentOption<T> {
  const SegmentOption({required this.value, required this.label});
  final T value;
  final String label;
}

/// Pill segmented control: Over/Under, Manual/Auto, Red/Black.
///
/// ```dart
/// SegmentedToggle<bool>(
///   options: const [SegmentOption(value: false, label: 'Under'), SegmentOption(value: true, label: 'Over')],
///   selected: over,
///   onChanged: (v) => setState(() => over = v),
/// )
/// ```
class SegmentedToggle<T> extends StatelessWidget {
  const SegmentedToggle({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.height = 48,
    this.activeColor,
    this.activeTextColor,
  });

  final List<SegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final double height;
  final Color? activeColor;
  final Color? activeTextColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(height),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: PressScale(
                onTap: () => onChanged(o.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: o.value == selected ? (activeColor ?? AppColors.inverse) : Colors.transparent,
                    borderRadius: BorderRadius.circular(height),
                  ),
                  child: Text(
                    o.label,
                    style: AppText.body(14,
                        weight: FontWeight.w700,
                        color: o.value == selected ? (activeTextColor ?? AppColors.onInverse) : AppColors.textMuted),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
