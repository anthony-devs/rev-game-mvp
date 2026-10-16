import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'slots_theme.dart';

class RaysPainter extends CustomPainter {
  RaysPainter({required this.onDeg, required this.periodDeg, required this.alpha, required this.fade, required this.rotation});
  final double onDeg, periodDeg, alpha, fade, rotation; // degrees

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.saveLayer(rect, Paint());
    final p = Paint()..color = Color.fromRGBO(255, 200, 61, alpha);
    for (double a = 0; a < 360; a += periodDeg) {
      canvas.drawArc(rect, (a + rotation) * math.pi / 180, onDeg * math.pi / 180, true, p);
    }
    final mask = Paint()
      ..blendMode = BlendMode.dstIn
      ..shader = RadialGradient(
        colors: const [Colors.black, Color(0x00000000)],
        stops: [0, fade],
      ).createShader(rect);
    canvas.drawRect(rect, mask);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RaysPainter old) => old.rotation != rotation || old.alpha != alpha;
}

class SparklePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final k = s.width / 24;
    final path = Path()
      ..moveTo(12 * k, 0)
      ..lineTo(14.5 * k, 9.5 * k)
      ..lineTo(24 * k, 12 * k)
      ..lineTo(14.5 * k, 14.5 * k)
      ..lineTo(12 * k, 24 * k)
      ..lineTo(9.5 * k, 14.5 * k)
      ..lineTo(0, 12 * k)
      ..lineTo(9.5 * k, 9.5 * k)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFE08A));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class TrianglePainter extends CustomPainter {
  TrianglePainter({required this.pointsRight});
  final bool pointsRight;
  @override
  void paint(Canvas canvas, Size s) {
    final path = Path();
    if (pointsRight) {
      path..moveTo(0, 0)..lineTo(s.width, s.height / 2)..lineTo(0, s.height)..close();
    } else {
      path..moveTo(s.width, 0)..lineTo(0, s.height / 2)..lineTo(s.width, s.height)..close();
    }
    canvas.drawPath(path, Paint()..color = kGold);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
