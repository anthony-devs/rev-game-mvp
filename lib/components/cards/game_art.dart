import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_colors.dart';

enum GameKind { slots, roulette, blackjack, dice, crash, soon }

/// Gradient colours per game, used by tiles and cards.
class GameArtStyle {
  const GameArtStyle(this.top, this.bottom, this.accent);
  final Color top;
  final Color bottom;
  final Color accent;

  static GameArtStyle of(GameKind k) {
    switch (k) {
      case GameKind.slots:
        return const GameArtStyle(Color(0xFF4A2A00), Color(0xFF1A0F00), AppColors.gold);
      case GameKind.roulette:
        return const GameArtStyle(Color(0xFF0B3B2A), Color(0xFF06150F), AppColors.green);
      case GameKind.blackjack:
        return const GameArtStyle(Color(0xFF2A1A4A), Color(0xFF110A1F), AppColors.purple);
      case GameKind.dice:
        return const GameArtStyle(Color(0xFF0A2F4A), Color(0xFF06131F), AppColors.blue);
      case GameKind.crash:
        return const GameArtStyle(Color(0xFF4A1014), Color(0xFF1A0507), AppColors.loss);
      case GameKind.soon:
        return const GameArtStyle(Color(0xFF232326), Color(0xFF121214), AppColors.textDim);
    }
  }
}

/// Painted artwork for a game (no image assets needed).
///
/// ```dart
/// GameArt(kind: GameKind.crash)
/// ```
class GameArt extends StatelessWidget {
  const GameArt({super.key, required this.kind, this.borderRadius = 20});

  final GameKind kind;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final s = GameArtStyle.of(kind);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [s.top, s.bottom]),
        ),
        child: SizedBox.expand(child: CustomPaint(painter: _ArtPainter(kind, s.accent))),
      ),
    );
  }
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.kind, this.color);
  final GameKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * .42);
    final u = math.min(size.width, size.height);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = u * .025
      ..color = color.withValues(alpha: .85)
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = color.withValues(alpha: .16);

    switch (kind) {
      case GameKind.slots:
        for (var i = -1; i <= 1; i++) {
          final r = RRect.fromRectAndRadius(
            Rect.fromCenter(center: c + Offset(i * u * .27, 0), width: u * .22, height: u * .38),
            Radius.circular(u * .04),
          );
          canvas.drawRRect(r, fill);
          canvas.drawRRect(r, stroke);
        }
        break;
      case GameKind.roulette:
        canvas.drawCircle(c, u * .30, fill);
        canvas.drawCircle(c, u * .30, stroke);
        canvas.drawCircle(c, u * .16, stroke);
        for (var i = 0; i < 12; i++) {
          final a = i * math.pi / 6;
          canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * (u * .16), c + Offset(math.cos(a), math.sin(a)) * (u * .30), stroke..strokeWidth = u * .012);
        }
        break;
      case GameKind.blackjack:
        for (var i = 0; i < 2; i++) {
          canvas.save();
          canvas.translate(c.dx + (i == 0 ? -u * .09 : u * .09), c.dy);
          canvas.rotate(i == 0 ? -.2 : .2);
          final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: u * .27, height: u * .38), Radius.circular(u * .04));
          canvas.drawRRect(r, i == 0 ? fill : Paint()..color = color.withValues(alpha: .28));
          canvas.drawRRect(r, stroke..strokeWidth = u * .025);
          canvas.restore();
        }
        break;
      case GameKind.dice:
        final r = RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: u * .40, height: u * .40), Radius.circular(u * .08));
        canvas.drawRRect(r, fill);
        canvas.drawRRect(r, stroke);
        final dot = Paint()..color = color;
        for (final o in const [Offset(-1, -1), Offset(1, -1), Offset(0, 0), Offset(-1, 1), Offset(1, 1)]) {
          canvas.drawCircle(c + o * (u * .1), u * .03, dot);
        }
        break;
      case GameKind.crash:
        final p = Path()..moveTo(size.width * .14, size.height * .66);
        p.cubicTo(size.width * .40, size.height * .66, size.width * .60, size.height * .52, size.width * .84, size.height * .14);
        canvas.drawPath(p, stroke..strokeWidth = u * .035);
        canvas.drawCircle(Offset(size.width * .84, size.height * .14), u * .04, Paint()..color = color);
        break;
      case GameKind.soon:
        canvas.drawCircle(c, u * .12, stroke);
        break;
    }
  }

  @override
  bool shouldRepaint(_ArtPainter old) => old.kind != kind || old.color != color;
}
