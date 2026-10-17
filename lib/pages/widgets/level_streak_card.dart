import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../components/components.dart';
import '../../user/bloc/profile_cubit.dart';
import '../../user/data/daily_rewards.dart';
import '../round_format.dart';
import '../get_credits_sheet.dart';

/// Level badge, XP bar and the 7 day streak (tap to open daily credits).
class LevelStreakCard extends StatelessWidget {
  const LevelStreakCard({super.key});

  @override
  Widget build(BuildContext context) {
    final progress = context.select((ProfileCubit c) => c.state.progress);
    final wallet = context.select((ProfileCubit c) => c.state.wallet);
    final now = DateTime.now();
    final dots = claimedDotsToday(wallet, progress, now);
    final streak = dots == 0 ? 0 : progress.streakDays;
    final ready = context.select((ProfileCubit c) => c.state.walletReady);
    final canClaim = ready && wallet.canClaimDaily(now);

    return PressScale(
      onTap: () => showGetCredits(context),
      scale: .99,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: AppColors.surface,
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: AppColors.purple,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('LEVEL', style: AppText.body(9, weight: FontWeight.w700, letterSpacing: 1, height: 1, color: Colors.white.withValues(alpha: .85))),
                  Text('${progress.level}', style: AppText.body(20, weight: FontWeight.w800, height: 1.1, color: Colors.white)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(levelTitle(progress.level), style: AppText.body(12, weight: FontWeight.w600)),
                      Text('${formatCredits(progress.xp, decimals: 0)} / ${formatCredits(progress.xpForNext, decimals: 0)} XP', style: AppText.body(11, weight: FontWeight.w600, color: AppColors.textDim, tabularFigures: true)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AppProgressBar(value: progress.fraction, color: AppColors.purple),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (var i = 1; i <= 7; i++) ...[
                        Container(width: 14, height: 6, decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: i <= dots ? AppColors.gold : AppColors.track)),
                        const SizedBox(width: 4),
                      ],
                      const SizedBox(width: 2),
                      Expanded(
                        child: Text(
                          canClaim ? 'Daily credits ready' : (streak > 0 ? '$streak day streak' : 'Start a streak'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body(10, weight: FontWeight.w600, color: canClaim ? AppColors.gold : AppColors.textDim),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
