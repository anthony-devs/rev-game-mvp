import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';

/// The REV GAMES chip mark: a ring of dashes around a circle with an R. Drawn in code, so it stays
/// sharp at every size and takes any colour.
///
/// ```dart
/// RevMark(size: 28)
/// RevMark(size: 20, color: Colors.white)
/// ```
class RevMark extends StatelessWidget {
  const RevMark({super.key, this.size = 28, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.gold;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MarkPainter(c),
        child: size < 16 ? null : Center(child: Text('R', style: TextStyle(fontFamily: AppText.family, fontSize: size * .46, fontWeight: FontWeight.w600, color: c, height: 1))),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final stroke = size.width * .075;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    const dashes = 12;
    const gap = .22; // share of each slot left empty
    final ring = Rect.fromCircle(center: c, radius: r - stroke / 2);
    for (var i = 0; i < dashes; i++) {
      final start = i * 2 * math.pi / dashes + gap * math.pi / dashes;
      canvas.drawArc(ring, start, (1 - gap) * 2 * math.pi / dashes, false, paint);
    }
    canvas.drawCircle(c, r * .66, paint..strokeWidth = stroke * .6);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color;
}

/// The mark followed by the REV GAMES name. Use it in headers.
class RevWordmark extends StatelessWidget {
  const RevWordmark({super.key, this.markSize = 30, this.textSize = 18});

  final double markSize;
  final double textSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RevMark(size: markSize),
        SizedBox(width: markSize * .3),
        Text('REV GAMES', maxLines: 1, style: AppText.heading(textSize, letterSpacing: -.4)),
      ],
    );
  }
}
