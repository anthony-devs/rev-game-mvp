import 'package:flutter/material.dart';

/// Shows a number that rolls to its new value instead of jumping (a balance, a total).
///
/// The first value appears at once; every change after that counts up or down in about a fifth
/// of a second. Does not move at all when the device asks for reduced motion.
///
/// ```dart
/// RollingNumber(value: balance, builder: (v) => Text(formatCredits(v)))
/// ```
class RollingNumber extends StatelessWidget {
  const RollingNumber({super.key, required this.value, required this.builder, this.duration = const Duration(milliseconds: 250)});

  final double value;
  final Widget Function(double value) builder;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value),
      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => builder(v),
    );
  }
}
