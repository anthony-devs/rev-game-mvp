import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_colors.dart';

/// Rising curve for the Crash game. The server sends the multiplier; this just draws it.
///
/// ```dart
/// CrashGraph(multiplier: m, busted: state == CrashState.bust)
/// ```
class CrashGraph extends StatelessWidget {
  const CrashGraph({super.key, required this.multiplier, this.busted = false, this.maxMultiplier = 10});

  final double multiplier;
  final bool busted;

  /// Value at which the curve reaches the top of the graph.
  final double maxMultiplier;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _CrashPainter(multiplier, busted, maxMultiplier),
    );
  }
}

class _CrashPainter extends CustomPainter {
  _CrashPainter(this.m, this.busted, this.maxM);
  final double m;
  final bool busted;
  final double maxM;

  @override
  void paint(Canvas canvas, Size size) {
    final color = busted ? AppColors.loss : AppColors.green;
    final grid = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    for (var i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final t = ((m - 1) / math.max(.0001, maxM - 1)).clamp(0.0, 1.0);
    const steps = 60;
    final path = Path()..moveTo(0, size.height);
    Offset end = Offset(0, size.height);
    for (var i = 1; i <= steps; i++) {
      final p = i / steps;
      final x = size.width * .92 * p * math.max(.15, math.sqrt(t));
      final y = size.height - size.height * .88 * t * math.pow(p, 2.2);
      end = Offset(x, y);
      path.lineTo(x, y);
    }

    final area = Path.from(path)
      ..lineTo(end.dx, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withValues(alpha: .28), color.withValues(alpha: 0)]).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    canvas.drawCircle(end, 7, Paint()..color = color);
    canvas.drawCircle(end, 14, Paint()..color = color.withValues(alpha: .25));
  }

  @override
  bool shouldRepaint(_CrashPainter old) => old.m != m || old.busted != busted || old.maxM != maxM;
}
