import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/formatters.dart';
import '../feedback/app_progress_bar.dart';

/// Player level, XP bar and streak.
///
/// ```dart
/// LevelProgressCard(level: 7, title: 'High Roller', xp: 640, xpMax: 1000, streakDays: 3)
/// ```
class LevelProgressCard extends StatelessWidget {
  const LevelProgressCard({
    super.key,
    required this.level,
    required this.xp,
    required this.xpMax,
    this.title,
    this.streakDays,
  });

  final int level;
  final String? title;
  final int xp;
  final int xpMax;
  final int? streakDays;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.purple, width: 2)),
                child: Text('$level', style: AppText.number(18, color: AppColors.purple)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LEVEL $level', style: AppText.label()),
                    if (title != null) Text(title!, style: AppText.body(17, weight: FontWeight.w700)),
                  ],
                ),
              ),
              if (streakDays != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('STREAK', style: AppText.label()),
                    Text('$streakDays days', style: AppText.body(15, weight: FontWeight.w700, color: AppColors.gold)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          AppProgressBar(value: xpMax == 0 ? 0 : xp / xpMax),
          const SizedBox(height: 8),
          Text('${formatCredits(xp, decimals: 0)} / ${formatCredits(xpMax, decimals: 0)} XP',
              style: AppText.body(12, color: AppColors.textDim)),
        ],
      ),
    );
  }
}
