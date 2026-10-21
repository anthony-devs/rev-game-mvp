import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_colors.dart';

enum GameKind { slots, roulette, blackjack, dice, crash, plinko, lucky7, mines, baccarat, wheel, keno, hilo, limbo, coinflip, rps, darts, scratch, diamonds, war, tower, chicken, pump, moles, soon }

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
      case GameKind.mines:
        return AppColors.purple;
      case GameKind.baccarat:
        return AppColors.green;
      case GameKind.wheel:
        return AppColors.gold;
      case GameKind.keno:
        return AppColors.blue;
      case GameKind.hilo:
        return AppColors.mint;
      case GameKind.limbo:
        return AppColors.blue;
      case GameKind.coinflip:
        return AppColors.gold;
      case GameKind.rps:
        return AppColors.purple;
      case GameKind.darts:
        return AppColors.loss;
      case GameKind.scratch:
        return AppColors.mint;
      case GameKind.diamonds:
        return AppColors.blue;
      case GameKind.war:
        return AppColors.green;
      case GameKind.tower:
        return AppColors.gold;
      case GameKind.chicken:
        return AppColors.green;
      case GameKind.pump:
        return AppColors.loss;
      case GameKind.moles:
        return AppColors.mint;
      case GameKind.soon:
        return AppColors.textDim;
    }
  }

  /// Flat panel colour: the accent washed into the surface.
  static Color panelOf(GameKind k) => Color.alphaBlend(accentOf(k).withValues(alpha: AppColors.light ? .12 : .16), AppColors.surface);
}

/// Artwork for a game: the illustrated cover from assets/games.
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
        child: SizedBox.expand(child: _cover(kind)),
      ),
    );
  }
}

/// The illustrated cover in assets/games, or the painted fallback when a game has none yet.
Widget _cover(GameKind kind) {
  final fallback = CustomPaint(painter: _ArtPainter(kind, GameArtStyle.accentOf(kind)));
  if (kind == GameKind.soon) return fallback;
  return Image.asset(
    'assets/games/${kind.name}.png',
    fit: BoxFit.cover,
    gaplessPlayback: true,
    filterQuality: FilterQuality.medium,
    errorBuilder: (_, __, ___) => fallback,
  );
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
      case GameKind.wheel:
        canvas.drawCircle(c, u * .3, fill);
        canvas.drawCircle(c, u * .3, stroke..strokeWidth = u * .025);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * (u * .06), c + Offset(math.cos(a), math.sin(a)) * (u * .3), stroke..strokeWidth = u * .012);
        }
        canvas.drawCircle(c, u * .05, Paint()..color = color);
        final pointer = Path()
          ..moveTo(c.dx - u * .035, c.dy - u * .34)
          ..lineTo(c.dx + u * .035, c.dy - u * .34)
          ..lineTo(c.dx, c.dy - u * .27)
          ..close();
        canvas.drawPath(pointer, Paint()..color = color);
        break;
      case GameKind.keno:
        final chosen = {0, 4, 5, 7};
        for (var gy = 0; gy < 3; gy++) {
          for (var gx = 0; gx < 3; gx++) {
            final o = c + Offset((gx - 1) * u * .17, (gy - 1) * u * .17);
            final on = chosen.contains(gy * 3 + gx);
            canvas.drawCircle(o, u * .06, on ? (Paint()..color = color.withValues(alpha: .5)) : fill);
            canvas.drawCircle(o, u * .06, stroke..strokeWidth = u * .014);
          }
        }
        break;
      case GameKind.hilo:
        final card = RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: u * .28, height: u * .4), Radius.circular(u * .04));
        canvas.drawRRect(card, fill);
        canvas.drawRRect(card, stroke..strokeWidth = u * .02);
        final up = Path()
          ..moveTo(c.dx - u * .06, c.dy - u * .02)
          ..lineTo(c.dx + u * .06, c.dy - u * .02)
          ..lineTo(c.dx, c.dy - u * .1)
          ..close();
        final down = Path()
          ..moveTo(c.dx - u * .06, c.dy + u * .02)
          ..lineTo(c.dx + u * .06, c.dy + u * .02)
          ..lineTo(c.dx, c.dy + u * .1)
          ..close();
        canvas.drawPath(up, Paint()..color = color);
        canvas.drawPath(down, Paint()..color = color.withValues(alpha: .45));
        break;
      case GameKind.limbo:
        final lp = Path()..moveTo(size.width * .18, size.height * .62)..lineTo(size.width * .82, size.height * .62);
        canvas.drawPath(lp, stroke..strokeWidth = u * .02);
        canvas.drawCircle(Offset(size.width * .66, size.height * .62), u * .05, Paint()..color = color);
        canvas.drawLine(Offset(size.width * .66, size.height * .62), Offset(size.width * .66, size.height * .22), stroke..strokeWidth = u * .03);
        break;
      case GameKind.coinflip:
        canvas.drawCircle(c, u * .24, fill);
        canvas.drawCircle(c, u * .24, stroke..strokeWidth = u * .03);
        canvas.drawCircle(c, u * .15, stroke..strokeWidth = u * .012);
        break;
      case GameKind.rps:
        for (var i = 0; i < 3; i++) {
          final a = -math.pi / 2 + i * math.pi * 2 / 3;
          final o = c + Offset(math.cos(a), math.sin(a)) * (u * .2);
          canvas.drawCircle(o, u * .075, i == 0 ? (Paint()..color = color.withValues(alpha: .4)) : fill);
          canvas.drawCircle(o, u * .075, stroke..strokeWidth = u * .016);
        }
        break;
      case GameKind.darts:
        for (final r in const [.3, .2, .1]) {
          canvas.drawCircle(c, u * r, stroke..strokeWidth = u * .016);
        }
        canvas.drawCircle(c, u * .035, Paint()..color = color);
        canvas.drawLine(c + Offset(u * .05, -u * .05), c + Offset(u * .26, -u * .26), stroke..strokeWidth = u * .03);
        break;
      case GameKind.scratch:
        for (var gy = 0; gy < 2; gy++) {
          for (var gx = 0; gx < 3; gx++) {
            final rr = RRect.fromRectAndRadius(Rect.fromCenter(center: c + Offset((gx - 1) * u * .19, (gy - .5) * u * .19), width: u * .16, height: u * .16), Radius.circular(u * .03));
            canvas.drawRRect(rr, gx == gy ? (Paint()..color = color.withValues(alpha: .4)) : fill);
            canvas.drawRRect(rr, stroke..strokeWidth = u * .012);
          }
        }
        break;
      case GameKind.diamonds:
        final dm = Path()
          ..moveTo(c.dx - u * .2, c.dy - u * .05)
          ..lineTo(c.dx - u * .1, c.dy - u * .18)
          ..lineTo(c.dx + u * .1, c.dy - u * .18)
          ..lineTo(c.dx + u * .2, c.dy - u * .05)
          ..lineTo(c.dx, c.dy + u * .22)
          ..close();
        canvas.drawPath(dm, fill);
        canvas.drawPath(dm, stroke..strokeWidth = u * .025);
        canvas.drawLine(Offset(c.dx - u * .2, c.dy - u * .05), Offset(c.dx + u * .2, c.dy - u * .05), stroke..strokeWidth = u * .012);
        break;
      case GameKind.war:
        for (var i = 0; i < 2; i++) {
          canvas.save();
          canvas.translate(c.dx + (i == 0 ? -u * .12 : u * .12), c.dy);
          canvas.rotate(i == 0 ? -.16 : .16);
          final rr = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: u * .26, height: u * .38), Radius.circular(u * .04));
          canvas.drawRRect(rr, i == 0 ? fill : Paint()..color = color.withValues(alpha: .3));
          canvas.drawRRect(rr, stroke..strokeWidth = u * .02);
          canvas.restore();
        }
        break;
      case GameKind.tower:
        for (var row = 0; row < 4; row++) {
          for (var col = 0; col < 3; col++) {
            final rr = RRect.fromRectAndRadius(Rect.fromCenter(center: c + Offset((col - 1) * u * .18, (row - 1.5) * u * .13), width: u * .15, height: u * .1), Radius.circular(u * .02));
            canvas.drawRRect(rr, row == 3 - col % 3 ? (Paint()..color = color.withValues(alpha: .4)) : fill);
            canvas.drawRRect(rr, stroke..strokeWidth = u * .01);
          }
        }
        break;
      case GameKind.chicken:
        for (var i = 0; i < 4; i++) {
          canvas.drawLine(Offset(size.width * (.2 + i * .2), size.height * .3), Offset(size.width * (.2 + i * .2), size.height * .58), stroke..strokeWidth = u * .016);
        }
        canvas.drawCircle(Offset(size.width * .5, size.height * .44), u * .06, Paint()..color = color);
        break;
      case GameKind.pump:
        canvas.drawOval(Rect.fromCenter(center: c - Offset(0, u * .03), width: u * .3, height: u * .38), fill);
        canvas.drawOval(Rect.fromCenter(center: c - Offset(0, u * .03), width: u * .3, height: u * .38), stroke..strokeWidth = u * .025);
        canvas.drawLine(c + Offset(0, u * .16), c + Offset(0, u * .28), stroke..strokeWidth = u * .016);
        break;
      case GameKind.moles:
        for (var i = 0; i < 3; i++) {
          final o = c + Offset((i - 1) * u * .2, u * .06);
          canvas.drawOval(Rect.fromCenter(center: o, width: u * .16, height: u * .07), fill);
          canvas.drawOval(Rect.fromCenter(center: o, width: u * .16, height: u * .07), stroke..strokeWidth = u * .012);
        }
        canvas.drawCircle(c + Offset(0, -u * .02), u * .05, Paint()..color = color);
        break;
      case GameKind.soon:
        canvas.drawCircle(c, u * .12, stroke);
        break;
    }
  }

  @override
  bool shouldRepaint(_ArtPainter old) => old.kind != kind || old.color != color;
}
