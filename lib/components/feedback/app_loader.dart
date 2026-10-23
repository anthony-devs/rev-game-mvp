import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import 'rev_mark.dart';

/// The app's loading animation: the REV chip mark, gently breathing. Use it everywhere something is
/// loading, so the look can be changed in this one place.
///
/// ```dart
/// const Center(child: AppLoader())
/// ```
class AppLoader extends StatefulWidget {
  const AppLoader({super.key, this.size = 36, this.color});

  /// Height and width of the mark.
  final double size;

  /// Mark colour. Defaults to the brand gold. Pass the surrounding foreground colour on coloured surfaces.
  final Color? color;

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'Loading',
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) {
            final t = still ? 1.0 : Curves.easeInOut.transform(_c.value);
            return Opacity(opacity: .45 + .55 * t, child: Transform.scale(scale: .86 + .14 * t, child: child));
          },
          child: RevMark(size: widget.size, color: widget.color ?? AppColors.gold),
        ),
      ),
    );
  }
}
