import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import 'roulette_number_cell.dart';

/// European wheel order, clockwise from 0.
const List<int> kWheelOrder = [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26];

/// Painted wheel. The SERVER decides the result; the client only turns the wheel.
/// Pass [rotation] (radians) from your own AnimationController, and [result] to show the landed number.
///
/// ```dart
/// RouletteWheel(rotation: anim.value * 2 * math.pi * 4, result: lastNumber)
/// ```
class RouletteWheel extends StatelessWidget {
  const RouletteWheel({super.key, this.rotation = 0, this.result, this.size = 260});

  final double rotation;
  final int? result;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(angle: rotation, child: CustomPaint(size: Size.square(size), painter: _WheelPainter())),
          Container(
            width: size * .34,
            height: size * .34,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.bg, border: Border.all(color: AppColors.lineStrong)),
            child: Text(result == null ? '-' : '$result', style: AppText.number(size * .12)),
          ),
          Positioned(top: 0, child: Icon(Icons.arrow_drop_down_rounded, size: size * .12, color: AppColors.gold)),
        ],
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    final seg = 2 * math.pi / kWheelOrder.length;
    for (var i = 0; i < kWheelOrder.length; i++) {
      final n = kWheelOrder[i];
      final col = rouletteColorOf(n);
      final paint = Paint()
        ..color = col == RouletteColor.red
            ? const Color(0xFFC62B2E)
            : (col == RouletteColor.green ? AppColors.greenDark : const Color(0xFF1C1C1E));
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2 + seg * i - seg / 2, seg, true, paint);
    }
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = AppColors.gold);
    canvas.drawCircle(c, r * .62, Paint()..color = AppColors.bg.withValues(alpha: .55));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
