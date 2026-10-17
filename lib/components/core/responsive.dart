import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Screen-size helpers. The app is designed phone-first and grows on iPads, Macs and the web:
///
///  * under [Breakpoints.tablet] (720): a phone. One column, floating tab bar.
///  * [Breakpoints.tablet]+: an iPad in portrait. Same layout with more room, content centred.
///  * [Breakpoints.wide] (900)+: an iPad in landscape, a Mac or a browser. Side navigation.
///  * [Breakpoints.twoPane] (840)+: game screens put the controls beside the table.
class Breakpoints {
  Breakpoints._();
  static const double tablet = 720;
  static const double twoPane = 840;
  static const double wide = 900;

  /// Widest the whole app is ever drawn (ultra-wide monitors get margins).
  static const double app = 1440;
}

extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  bool get isTablet => screenWidth >= Breakpoints.tablet;
  bool get isWide => screenWidth >= Breakpoints.wide;
  bool get isTwoPane => screenWidth >= Breakpoints.twoPane;
}

/// Centres [child] and stops it growing wider than [maxWidth]. On a phone it changes nothing.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 720});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
    );
  }
}

/// How many game tiles fit across [width].
int tileColumns(double width) {
  if (width < 560) return 3;
  if (width < 820) return 4;
  if (width < 1100) return 5;
  return math.min(7, 6 + ((width - 1100) ~/ 260));
}
