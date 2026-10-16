import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';

/// 0 to 100 slider track for the Dice game, with the win zone highlighted
/// and an optional marker for the last roll.
///
/// ```dart
/// DiceTrack(target: 50, over: true, onChanged: (v) => setState(() => target = v), lastRoll: 63.4)
/// ```
class DiceTrack extends StatelessWidget {
  const DiceTrack({
    super.key,
    required this.target,
    required this.over,
    required this.onChanged,
    this.lastRoll,
    this.min = 2,
    this.max = 98,
    this.enabled = true,
  });

  final double target;

  /// `true` wins when the roll is above [target], `false` when below.
  final bool over;
  final ValueChanged<double> onChanged;
  final double? lastRoll;
  final double min;
  final double max;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth;
            double x(double v) => w * v / 100;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: enabled ? (d) => onChanged((d.localPosition.dx / w * 100).clamp(min, max).roundToDouble()) : null,
              onTapDown: enabled ? (d) => onChanged((d.localPosition.dx / w * 100).clamp(min, max).roundToDouble()) : null,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 18,
                    child: Container(height: 12, decoration: BoxDecoration(color: AppColors.track, borderRadius: BorderRadius.circular(6))),
                  ),
                  Positioned(
                    left: over ? x(target) : 0,
                    width: over ? w - x(target) : x(target),
                    top: 18,
                    child: Container(height: 12, decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(6))),
                  ),
                  if (lastRoll != null)
                    Positioned(left: x(lastRoll!) - 1.5, top: 8, child: Container(width: 3, height: 32, color: AppColors.gold)),
                  Positioned(
                    left: x(target) - 14,
                    top: 10,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 8)],
                        border: Border.all(color: AppColors.bg, width: 4),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final t in const ['0', '25', '50', '75', '100']) Text(t, style: AppText.number(11, color: AppColors.textFaint, weight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }
}
