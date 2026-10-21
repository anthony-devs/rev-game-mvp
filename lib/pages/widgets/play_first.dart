import 'package:flutter/material.dart';

import '../../components/components.dart';
import '../../model/model.dart';
import '../round_format.dart';

/// The three games to put in front of every player: a wide Slots card, then Lucky Wheel and Plinko
/// side by side. Big cover art, a gold badge and a Play button, so they are the first thing seen.
class PlayFirst extends StatelessWidget {
  const PlayFirst({super.key, required this.slots, required this.wheel, required this.plinko, required this.onOpen});

  final GameInfo? slots, wheel, plinko;
  final void Function(GameInfo) onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      if (slots != null) _Card(game: slots!, height: 190, eyebrow: 'TOP PICK', line: 'Spin the reels and chase the jackpot', onTap: () => onOpen(slots!)),
      if (slots != null && (wheel != null || plinko != null)) const SizedBox(height: 12),
      if (wheel != null || plinko != null)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (wheel != null) Expanded(child: _Card(game: wheel!, height: 190, eyebrow: 'HOT', line: 'Spin and win up to 10x', onTap: () => onOpen(wheel!))),
          if (wheel != null && plinko != null) const SizedBox(width: 12),
          if (plinko != null) Expanded(child: _Card(game: plinko!, height: 190, eyebrow: 'HOT', line: 'Drop the ball, win big', onTap: () => onOpen(plinko!))),
        ]),
    ]);
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.game, required this.height, required this.eyebrow, required this.line, required this.onTap});

  final GameInfo game;
  final double height;
  final String eyebrow, line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.gold, width: 2)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(fit: StackFit.expand, children: [
            GameArt(kind: game.kind, borderRadius: 0),
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(8)),
                child: Text(eyebrow, style: AppText.body(10, weight: FontWeight.w800, color: const Color(0xFF14141A), letterSpacing: 1, height: 1)),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black.withValues(alpha: .62),
                padding: const EdgeInsets.fromLTRB(14, 10, 12, 12),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(game.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(17, weight: FontWeight.w800, color: Colors.white, height: 1.15)),
                      const SizedBox(height: 2),
                      Text(line, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.body(11.5, color: const Color(0xFFD5D5DD), height: 1.25)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow_rounded, color: Color(0xFF14141A), size: 24),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
