import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_colors.dart';

enum GameKind { slots, roulette, blackjack, dice, crash, plinko, lucky7, fruit, diamond, mines, baccarat, soon }

/// Accent colour per game, used by tiles and cards.
class GameArtStyle {
  const GameArtStyle._();

  static Color accentOf(GameKind k) {
    switch (k) {
      case GameKind.slots:
        return AppColors.gold;
      case GameKind.roulette:
        return AppColors.green;
      case GameKind.blackjack:
        return AppColors.purple;
      case GameKind.dice:
        return AppColors.blue;
      case GameKind.crash:
        return AppColors.loss;
      case GameKind.plinko:
        return AppColors.mint;
      case GameKind.lucky7:
        return AppColors.goldSoft;
      case GameKind.fruit:
        return AppColors.loss;
      case GameKind.diamond:
        return AppColors.blue;
      case GameKind.mines:
        return AppColors.purple;
      case GameKind.baccarat:
        return AppColors.green;
      case GameKind.soon:
        return AppColors.textDim;
    }
  }

  /// Flat panel colour: the accent washed into the surface.
  static Color panelOf(GameKind k) => Color.alphaBlend(accentOf(k).withValues(alpha: AppColors.light ? .12 : .16), AppColors.surface);
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: ColoredBox(
        color: GameArtStyle.panelOf(kind),
        child: SizedBox.expand(child: CustomPaint(painter: _ArtPainter(kind, GameArtStyle.accentOf(kind)))),
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
      case GameKind.plinko:
        // A triangle of pegs with the ball dropping in from the top.
        final peg = Paint()..color = color.withValues(alpha: .85);
        for (var row = 0; row < 4; row++) {
          for (var i = 0; i <= row + 1; i++) {
            final x = c.dx + (i - (row + 1) / 2) * u * .17;
            canvas.drawCircle(Offset(x, c.dy - u * .12 + row * u * .14), u * .022, peg);
          }
        }
        canvas.drawCircle(Offset(c.dx + u * .02, c.dy - u * .27), u * .045, Paint()..color = color);
        break;
      case GameKind.lucky7:
        final seven = Path()
          ..moveTo(c.dx - u * .17, c.dy - u * .2)
          ..lineTo(c.dx + u * .17, c.dy - u * .2)
          ..lineTo(c.dx - u * .05, c.dy + u * .22);
        canvas.drawPath(seven, stroke..strokeWidth = u * .06);
        canvas.drawCircle(c + Offset(u * .26, -u * .22), u * .03, Paint()..color = color);
        canvas.drawCircle(c + Offset(-u * .27, u * .2), u * .02, Paint()..color = color);
        break;
      case GameKind.fruit:
        final cherry = Paint()..color = color;
        for (final o in [Offset(-u * .1, u * .12), Offset(u * .1, u * .16)]) {
          canvas.drawCircle(c + o, u * .1, fill);
          canvas.drawCircle(c + o, u * .1, stroke..strokeWidth = u * .025);
          canvas.drawCircle(c + o + Offset(-u * .03, -u * .03), u * .02, cherry);
        }
        final stem = Path()
          ..moveTo(c.dx - u * .1, c.dy + u * .02)
          ..quadraticBezierTo(c.dx - u * .06, c.dy - u * .16, c.dx + u * .04, c.dy - u * .22)
          ..moveTo(c.dx + u * .1, c.dy + u * .06)
          ..quadraticBezierTo(c.dx + u * .1, c.dy - u * .14, c.dx + u * .04, c.dy - u * .22);
        canvas.drawPath(stem, stroke..strokeWidth = u * .02);
        break;
      case GameKind.diamond:
        final gem = Path()
          ..moveTo(c.dx - u * .2, c.dy - u * .05)
          ..lineTo(c.dx - u * .1, c.dy - u * .2)
          ..lineTo(c.dx + u * .1, c.dy - u * .2)
          ..lineTo(c.dx + u * .2, c.dy - u * .05)
          ..lineTo(c.dx, c.dy + u * .24)
          ..close();
        canvas.drawPath(gem, fill);
        canvas.drawPath(gem, stroke..strokeWidth = u * .025);
        canvas.drawLine(Offset(c.dx - u * .2, c.dy - u * .05), Offset(c.dx + u * .2, c.dy - u * .05), stroke..strokeWidth = u * .015);
        canvas.drawLine(Offset(c.dx - u * .06, c.dy - u * .2), Offset(c.dx - u * .1, c.dy - u * .05), stroke);
        canvas.drawLine(Offset(c.dx + u * .06, c.dy - u * .2), Offset(c.dx + u * .1, c.dy - u * .05), stroke);
        break;
      case GameKind.mines:
        final cell = u * .15;
        for (var gy = -1; gy <= 1; gy++) {
          for (var gx = -1; gx <= 1; gx++) {
            final r = RRect.fromRectAndRadius(Rect.fromCenter(center: c + Offset(gx * (cell + u * .025), gy * (cell + u * .025)), width: cell, height: cell), Radius.circular(u * .025));
            final hit = gx == 1 && gy == 0;
            canvas.drawRRect(r, hit ? (Paint()..color = color.withValues(alpha: .35)) : fill);
            canvas.drawRRect(r, stroke..strokeWidth = u * .012);
          }
        }
        final mc = c + Offset(cell + u * .025, 0);
        canvas.drawCircle(mc, u * .035, Paint()..color = color);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          canvas.drawLine(mc + Offset(math.cos(a), math.sin(a)) * (u * .04), mc + Offset(math.cos(a), math.sin(a)) * (u * .06), stroke..strokeWidth = u * .012);
        }
        break;
      case GameKind.baccarat:
        for (var i = 0; i < 2; i++) {
          canvas.save();
          canvas.translate(c.dx + (i == 0 ? -u * .12 : u * .12), c.dy);
          canvas.rotate(i == 0 ? -.14 : .14);
          final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: u * .26, height: u * .38), Radius.circular(u * .04));
          canvas.drawRRect(r, i == 0 ? fill : Paint()..color = color.withValues(alpha: .28));
          canvas.drawRRect(r, stroke..strokeWidth = u * .02);
          final pip = Paint()..color = color;
          for (final o in i == 0 ? const [Offset(0, -1), Offset(0, 1)] : const [Offset(-1, -1), Offset(1, -1), Offset(0, 0), Offset(-1, 1), Offset(1, 1)]) {
            canvas.drawCircle(Offset(o.dx * u * .05, o.dy * u * .09), u * .02, pip);
          }
          canvas.restore();
        }
        break;
      case GameKind.soon:
        canvas.drawCircle(c, u * .12, stroke);
        break;
    }
  }

  @override
  bool shouldRepaint(_ArtPainter old) => old.kind != kind || old.color != color;
}
