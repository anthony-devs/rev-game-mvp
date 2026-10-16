import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/formatters.dart';

/// Result banner shown after a round. [amount] > 0 is a win, <= 0 a loss.
///
/// ```dart
/// WinBanner(amount: 1020, caption: 'Dice win')
/// WinBanner(amount: -100, caption: 'Better luck next time')
/// ```
class WinBanner extends StatelessWidget {
  const WinBanner({super.key, required this.amount, this.caption, this.winLabel = 'YOU WON', this.lossLabel = 'ROUND LOST'});

  final double amount;
  final String? caption;
  final String winLabel;
  final String lossLabel;

  @override
  Widget build(BuildContext context) {
    final win = amount > 0;
    final c = win ? AppColors.green : AppColors.loss;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: .5)),
      ),
      child: Column(
        children: [
          Text(win ? winLabel : lossLabel, style: AppText.label(color: c)),
          const SizedBox(height: 4),
          Text(formatSigned(amount), style: AppText.number(28, color: c, shadows: win ? AppText.glow(c, opacity: .4) : null)),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption!, style: AppText.body(12, color: AppColors.textDim)),
          ],
        ],
      ),
    );
  }
}
