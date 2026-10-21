import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rev_game_mvp/components/components.dart';

import '../crash.dart';
import '../crash_server.dart';

/// The graph panel: curve, big multiplier and the character.
class CrashStage extends StatelessWidget {
  const CrashStage({
    super.key,
    required this.phase,
    required this.multiplier,
    required this.roundNumber,
    this.cashedAt,
  });

  final RoundPhase phase;
  final double multiplier;
  final int roundNumber;

  /// Set once the player has cashed out in this round.
  final double? cashedAt;

  CrashState get _charState {
    switch (phase) {
      case RoundPhase.running:
        return CrashState.Run;
      case RoundPhase.crashed:
        return CrashState.Dead;
      case RoundPhase.betting:
        return CrashState.Idle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final crashed = phase == RoundPhase.crashed;
    final betting = phase == RoundPhase.betting;
    final cashed = cashedAt != null;
    final tone = crashed ? AppColors.loss : AppColors.green;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, box) {
          final charH = math.min(150.0, box.maxHeight * .42);
          return Stack(
            children: [
              Positioned.fill(
                child: betting
                    ? const SizedBox.shrink()
                    : CrashGraph(multiplier: multiplier, busted: crashed, maxMultiplier: math.max(4, multiplier * 1.4)),
              ),
              if (betting) const Positioned.fill(child: CustomPaint(painter: _GridPainter())),
              Align(
                alignment: const Alignment(0, -.35),
                child: betting
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('READY', style: AppText.label()),
                          const SizedBox(height: 4),
                          Text('Place your bet', style: AppText.body(22, weight: FontWeight.w700)),
                        ],
                      )
                    : MultiplierDisplay(
                        value: multiplier,
                        size: 60,
                        color: crashed ? AppColors.loss : (cashed ? AppColors.gold : AppColors.text),
                        caption: crashed ? 'CRASHED AT' : (cashed ? 'CASHED OUT AT ${cashedAt!.toStringAsFixed(2)}x' : null),
                      ),
              ),
              Positioned(
                left: 10,
                bottom: 28,
                child: CrashCharacter(state: _charState, height: charH),
              ),
              Positioned(
                left: 14,
                bottom: 10,
                child: Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: tone)),
                  const SizedBox(width: 6),
                  Text('Round $roundNumber', style: AppText.body(11, weight: FontWeight.w600, color: AppColors.textDim)),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    for (var i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
