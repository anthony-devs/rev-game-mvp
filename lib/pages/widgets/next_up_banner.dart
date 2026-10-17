import 'package:flutter/material.dart';

import '../../catalog/upcoming.dart';
import '../../components/components.dart';
import '../../model/model.dart';

/// The banner at the top of "Coming soon": the next game, with its artwork and a way in.
class NextUpBanner extends StatelessWidget {
  const NextUpBanner({super.key, required this.game, required this.onTap, this.joined = false});

  final GameInfo game;
  final VoidCallback onTap;
  final bool joined;

  @override
  Widget build(BuildContext context) {
    final info = upcomingInfoFor(game);
    final accent = info.accent;
    return PressScale(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: 'Next up: ${game.name}. ${info.tagline}',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 148,
            decoration: BoxDecoration(border: Border.all(color: accent.withValues(alpha: .45)), borderRadius: BorderRadius.circular(20)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                GameArt(kind: info.kind, borderRadius: 0),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [AppColors.bg.withValues(alpha: .92), AppColors.bg.withValues(alpha: .15)]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('NEXT UP', style: AppText.label(color: accent)),
                      const SizedBox(height: 4),
                      Text(game.name, style: AppText.body(22, weight: FontWeight.w800, height: 1.1)),
                      const SizedBox(height: 4),
                      Text(info.tagline, style: AppText.body(13, color: AppColors.textSoft)),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: accent.withValues(alpha: joined ? .15 : .9), borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(joined ? Icons.check_rounded : Icons.notifications_none_rounded, size: 14, color: joined ? accent : AppColors.onAccent),
                            const SizedBox(width: 6),
                            Text(joined ? 'On the waitlist' : 'Join the waitlist', style: AppText.body(12, weight: FontWeight.w700, color: joined ? accent : AppColors.onAccent)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
