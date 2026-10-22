import 'package:flutter/material.dart';

import '../core/app_colors.dart';

/// Pulsing placeholder block for loading screens.
///
/// ```dart
/// SkeletonBox(height: 120, radius: 20)
/// SkeletonBox(width: 80, height: 14)
/// ```
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.width, this.height = 16, this.radius = 10});

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          // Still (no pulse) when the device asks for reduced motion.
          color: Color.lerp(AppColors.surfaceAlt, AppColors.track, MediaQuery.disableAnimationsOf(context) ? .5 : _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// A few placeholder rows that stand in for a list or a form while it loads.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 3, this.rowHeight = 56, this.gap = 12, this.radius = 16});

  final int rows;
  final double rowHeight;
  final double gap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows; i++) ...[
          if (i > 0) SizedBox(height: gap),
          SkeletonBox(height: rowHeight, radius: radius),
        ],
      ],
    );
  }
}
