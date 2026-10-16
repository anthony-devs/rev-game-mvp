import 'package:flutter/material.dart';

import 'multiplier_pill.dart';

/// Horizontal strip of recent multipliers, newest first.
///
/// ```dart
/// HistoryStrip(values: [1.12, 4.8, 2.01, 18.4])
/// ```
class HistoryStrip extends StatelessWidget {
  const HistoryStrip({
    super.key,
    required this.values,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.decimals = 2,
    this.colorFor,
  });

  final List<double> values;
  final EdgeInsets padding;
  final int decimals;

  /// Override the colour per value. `null` uses the default tone.
  final Color? Function(double value)? colorFor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => MultiplierPill(value: values[i], fontSize: 12, decimals: decimals, color: colorFor?.call(values[i])),
      ),
    );
  }
}
