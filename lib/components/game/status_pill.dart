import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';

/// Short status chip: WAITING, LIVE, WON, BUST.
///
/// ```dart
/// StatusPill(label: 'LIVE', color: AppColors.green, pulsing: true)
/// ```
class StatusPill extends StatefulWidget {
  const StatusPill({super.key, required this.label, this.color, this.pulsing = false});

  final String label;
  final Color? color;
  final bool pulsing;

  @override
  State<StatusPill> createState() => _StatusPillState();
}

class _StatusPillState extends State<StatusPill> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (widget.color ?? AppColors.green).withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (widget.color ?? AppColors.green).withValues(alpha: .5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: (widget.color ?? AppColors.green).withValues(alpha: widget.pulsing ? .4 + .6 * _c.value : 1)),
            ),
          ),
          const SizedBox(width: 8),
          Text(widget.label, style: AppText.body(11, weight: FontWeight.w800, color: (widget.color ?? AppColors.green), letterSpacing: 1.2, height: 1)),
        ],
      ),
    );
  }
}
