import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../components/components.dart';

/// The peg board and the slots under it. The ball follows [path] (0 = left, 1 = right at every
/// row) as [progress] goes from 0 to 1. The result is already decided by the server; this only
/// draws it.
class PlinkoBoard extends StatelessWidget {
  const PlinkoBoard({
    super.key,
    required this.rows,
    required this.multipliers,
    required this.path,
    required this.progress,
    this.landedSlot,
    this.loading = false,
  });

  final int rows;

  /// `rows + 1` slot payouts. Empty while the board is loading.
  final List<double> multipliers;
  final List<int> path;
  final double progress;
  final int? landedSlot;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = w * (0.78 + rows * 0.02);
        return Semantics(
          label: 'Plinko board with $rows rows',
          child: CustomPaint(
            size: Size(w, h),
            painter: _BoardPainter(
              rows: rows,
              multipliers: multipliers,
              path: path,
              progress: progress,
              landed: landedSlot,
              peg: AppColors.textFaint,
              ball: AppColors.gold,
              text: AppColors.text,
              dim: AppColors.textDim,
              surface: AppColors.surfaceAlt,
              good: AppColors.green,
              hot: AppColors.loss,
              mid: AppColors.gold,
              loading: loading,
            ),
          ),
        );
      },
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.rows,
    required this.multipliers,
    required this.path,
    required this.progress,
    required this.landed,
    required this.peg,
    required this.ball,
    required this.text,
    required this.dim,
    required this.surface,
    required this.good,
    required this.hot,
    required this.mid,
    required this.loading,
  });

  final int rows;
  final List<double> multipliers;
  final List<int> path;
  final double progress;
  final int? landed;
  final Color peg, ball, text, dim, surface, good, hot, mid;
  final bool loading;

  // Same look as the roulette numbers: solid rounded cells, white figures.
  Color _slotColor(double m) {
    if (m >= 10) return const Color(0xFFC62B2E); // red
    if (m >= 3) return const Color(0xFFD9822B); // amber
    if (m >= 1) return AppColors.greenDark;
    return const Color(0xFF1C1C1E); // black
  }

  static String _label(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(m >= 10000 ? 0 : 1)}k';
    if (m >= 100) return m.toStringAsFixed(0);
    if (m >= 10) return m.toStringAsFixed(m == m.roundToDouble() ? 0 : 1);
    return m.toStringAsFixed(m == m.roundToDouble() ? 0 : 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final slots = rows + 1;
    final slotH = math.min(30.0, size.width / slots * 1.3);
    final spacing = size.width / (slots + 0.4); // distance between neighbouring pegs
    final top = 14.0;
    final bottomPad = slotH + 10;
    final dy = (size.height - top - bottomPad) / rows;
    final cx = size.width / 2;
    final pegR = math.max(2.0, spacing * 0.11);
    final ballR = math.max(5.0, spacing * 0.3);

    double px(int j, int r) => cx + (j - r / 2) * spacing; // x of peg j in row r
    double py(int r) => top + r * dy;

    final pegPaint = Paint()..color = peg.withValues(alpha: .9);
    for (var r = 0; r < rows; r++) {
      for (var j = 0; j <= r; j++) {
        canvas.drawCircle(Offset(px(j, r), py(r)), pegR, pegPaint);
      }
    }

    // Slots under the last row.
    final slotY = top + rows * dy + 6;
    final slotW = spacing * 0.92;
    for (var i = 0; i < slots; i++) {
      final x = cx + (i - rows / 2) * spacing;
      final m = i < multipliers.length ? multipliers[i] : 0.0;
      final ready = !loading && multipliers.isNotEmpty;
      final isHit = landed == i;
      final fill = ready ? _slotColor(m) : surface;
      final rect = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, slotY + slotH / 2), width: slotW, height: slotH), Radius.circular(slotW * .24));
      canvas.drawRRect(rect, Paint()..color = fill.withValues(alpha: isHit || landed == null ? 1 : .55));
      canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHit ? 2.4 : 1
          ..color = isHit ? mid : AppColors.line,
      );
      if (ready) {
        final label = _label(m);
        final fontSize = math.max(7.5, math.min(12.5, slotW * (label.length > 3 ? .3 : label.length > 2 ? .36 : .46)));
        final tp = TextPainter(
          text: TextSpan(text: label, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          maxLines: 1,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, slotY + (slotH - tp.height) / 2));
      }
    }

    // The ball.
    if (path.length == rows && progress > 0) {
      final p = progress.clamp(0.0, 1.0) * rows;
      final r = math.min(rows - 1, p.floor());
      final u = p >= rows ? 1.0 : p - r; // 0..1 inside this row
      var k = 0; // rights so far, before row r
      for (var i = 0; i < r; i++) {
        k += path[i];
      }
      final k2 = k + path[r];
      final x0 = px(k, r);
      final x1 = cx + (k2 - (r + 1) / 2) * spacing;
      final y0 = py(r) - ballR - pegR;
      final y1 = r + 1 < rows ? py(r + 1) - ballR - pegR : slotY + slotH / 2;
      final ease = u * u * (3 - 2 * u);
      final hop = -dy * 0.55 * 4 * u * (1 - u); // a small bounce off each peg
      final pos = Offset(x0 + (x1 - x0) * ease, y0 + (y1 - y0) * ease + hop);
      canvas.drawCircle(pos.translate(0, 2), ballR, Paint()..color = const Color(0x55000000));
      canvas.drawCircle(pos, ballR, Paint()..color = ball);
      canvas.drawCircle(pos.translate(-ballR * .3, -ballR * .3), ballR * .28, Paint()..color = const Color(0x66FFFFFF));
    }
  }

  @override
  bool shouldRepaint(_BoardPainter o) =>
      o.progress != progress || o.rows != rows || o.landed != landed || o.loading != loading || !_same(o.multipliers, multipliers) || o.path != path || o.peg != peg;

  static bool _same(List<double> a, List<double> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
