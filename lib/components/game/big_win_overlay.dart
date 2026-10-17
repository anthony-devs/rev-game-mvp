import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../buttons/app_button.dart';
import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/formatters.dart';

/// Full-screen celebration. Show with [showBigWin] or place it in a Stack.
///
/// ```dart
/// showBigWin(context, amount: 12400, title: 'BIG WIN', multiplier: 24.8);
/// ```
Future<void> showBigWin(BuildContext context, {required double amount, String title = 'BIG WIN', double? multiplier, int multiplierDecimals = 2, String? caption, Widget? content, String buttonLabel = 'Collect'}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: .85),
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (ctx, _, __) => BigWinOverlay(
      amount: amount,
      title: title,
      multiplier: multiplier,
      multiplierDecimals: multiplierDecimals,
      caption: caption,
      content: content,
      buttonLabel: buttonLabel,
      onCollect: () => Navigator.of(ctx).pop(),
    ),
  );
}

class BigWinOverlay extends StatefulWidget {
  const BigWinOverlay({super.key, required this.amount, required this.onCollect, this.title = 'BIG WIN', this.multiplier, this.multiplierDecimals = 2, this.caption, this.content, this.buttonLabel = 'Collect'});

  final double amount;
  final String title;
  final double? multiplier;
  final int multiplierDecimals;

  /// Small line under the multiplier (e.g. "3x Seven on a 100 bet").
  final String? caption;

  /// Optional widget between the title and the amount (e.g. the winning symbols).
  final Widget? content;
  final String buttonLabel;
  final VoidCallback onCollect;

  @override
  State<BigWinOverlay> createState() => _BigWinOverlayState();
}

class _BigWinOverlayState extends State<BigWinOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(child: AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: _RaysPainter(_c.value)))),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title, style: AppText.heading(40, color: AppColors.gold, letterSpacing: 2)),
              if (widget.content != null) ...[const SizedBox(height: 20), widget.content!],
              const SizedBox(height: 16),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: widget.amount),
                duration: const Duration(milliseconds: 1400),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => Text(formatCredits(v, decimals: 0), style: AppText.number(48, color: AppColors.gold, shadows: AppText.glow(AppColors.gold))),
              ),
              if (widget.multiplier != null) ...[
                const SizedBox(height: 6),
                Text(formatMultiplier(widget.multiplier!, decimals: widget.multiplierDecimals), style: AppText.number(18, color: AppColors.mint)),
              ],
              if (widget.caption != null) ...[
                const SizedBox(height: 10),
                Text(widget.caption!, style: AppText.body(14, weight: FontWeight.w600, color: AppColors.textSoft)),
              ],
              const SizedBox(height: 36),
              SizedBox(width: 240, child: AppButton(label: widget.buttonLabel, onPressed: widget.onCollect, variant: AppButtonVariant.gold)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RaysPainter extends CustomPainter {
  _RaysPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * .42);
    final len = size.longestSide;
    const n = 14;
    for (var i = 0; i < n; i++) {
      final a = t * 2 * math.pi + i * 2 * math.pi / n;
      final w = math.pi / n * .55;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + math.cos(a - w) * len, c.dy + math.sin(a - w) * len)
        ..lineTo(c.dx + math.cos(a + w) * len, c.dy + math.sin(a + w) * len)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = AppColors.gold.withValues(alpha: .1),
      );
    }
  }

  @override
  bool shouldRepaint(_RaysPainter old) => old.t != t;
}
