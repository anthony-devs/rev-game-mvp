import 'package:flutter/material.dart';

import '../buttons/app_button.dart';
import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/formatters.dart';

/// Daily credits card with a Claim button or a countdown.
///
/// ```dart
/// DailyRewardCard(amount: 5000, onClaim: claim)                       // ready
/// DailyRewardCard(amount: 5000, onClaim: null, nextInSeconds: 3600)   // cooling down
/// ```
class DailyRewardCard extends StatelessWidget {
  const DailyRewardCard({super.key, required this.amount, required this.onClaim, this.nextInSeconds, this.title = 'Daily credits'});

  final double amount;
  final String title;
  final VoidCallback? onClaim;

  /// When set, the button is disabled and a countdown is shown.
  final int? nextInSeconds;

  @override
  Widget build(BuildContext context) {
    final waiting = nextInSeconds != null;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.gold.withValues(alpha: .4)),
        gradient: LinearGradient(colors: [AppColors.gold.withValues(alpha: .16), AppColors.gold.withValues(alpha: .04)]),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.toUpperCase(), style: AppText.label(color: AppColors.gold)),
                const SizedBox(height: 4),
                Text('+${formatCredits(amount, decimals: 0)}', style: AppText.number(24, color: AppColors.gold)),
                if (waiting) ...[
                  const SizedBox(height: 4),
                  Text('Next in ${formatCountdown(nextInSeconds!)}', style: AppText.body(12, color: AppColors.textDim)),
                ],
              ],
            ),
          ),
          AppButton(
            label: waiting ? 'Claimed' : 'Claim',
            onPressed: waiting ? null : onClaim,
            variant: AppButtonVariant.gold,
            expanded: false,
            height: 46,
            fontSize: 14,
          ),
        ],
      ),
    );
  }
}
