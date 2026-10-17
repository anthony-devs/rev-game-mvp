import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/formatters.dart';
import '../core/press_scale.dart';

/// Row of dashed chip circles for picking a stake (Roulette, Blackjack).
///
/// ```dart
/// BetChipPicker(values: const [10, 50, 100, 500, 1000], selected: chip, onSelected: (v) => setState(() => chip = v))
/// ```
class BetChipPicker extends StatelessWidget {
  const BetChipPicker({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelected,
    this.size = 54,
    this.color,
  });

  final List<double> values;
  final double selected;
  final ValueChanged<double> onSelected;
  final double size;
  final Color? color;

  static String _short(double v) {
    if (v >= 1000 && v % 1000 == 0) return '${(v / 1000).toStringAsFixed(0)}K';
    return formatCredits(v, decimals: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final v in values)
          PressScale(
            onTap: () => onSelected(v),
            child: SizedBox(
              width: size,
              height: size,
              child: CustomPaint(
                painter: _ChipPainter(color: v == selected ? (color ?? AppColors.gold) : AppColors.textFaint, active: v == selected),
                child: Center(
                  child: Text(
                    _short(v),
                    style: AppText.number(size * .26, color: v == selected ? (color ?? AppColors.gold) : AppColors.textSoft),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ChipPainter extends CustomPainter {
  _ChipPainter({required this.color, required this.active});
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    if (active) {
      canvas.drawCircle(c, r, Paint()..color = color.withValues(alpha: .14));
    }
    canvas.drawCircle(c, r - 1, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color);
    // dashed inner ring
    final ring = Path()..addOval(Rect.fromCircle(center: c, radius: r - 7));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color.withValues(alpha: .7);
    for (final m in ring.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 4), paint);
        d += 8;
      }
    }
  }

  @override
  bool shouldRepaint(_ChipPainter old) => old.color != color || old.active != active;
}
