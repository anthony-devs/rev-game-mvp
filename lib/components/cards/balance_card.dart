import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/play_mode.dart';
import '../core/rolling_number.dart';
import '../feedback/demo_badge.dart';

/// Big balance card for the Wallet screen. Put action buttons in [actions].
///
/// ```dart
/// BalanceCard(balance: 94250, actions: [AppButton(label: 'Get coins', onPressed: open)])
/// ```
class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key, required this.balance, this.label = 'Available coins', this.actions = const [], this.header});

  final double balance;
  final String label;
  final List<Widget> actions;

  /// Shown above the balance (the Demo / Live switch).
  final Widget? header;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(valueListenable: PlayMode.live, builder: (context, live, _) => _card(live));

  Widget _card(bool live) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: AppColors.surface,
        border: Border.all(color: live ? AppColors.loss.withValues(alpha: .6) : AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null) ...[header!, const SizedBox(height: 16)],
          Row(children: [Text(label.toUpperCase(), style: AppText.label()), const SizedBox(width: 10), live ? DemoBadge(label: 'LIVE', color: AppColors.loss) : DemoBadge()]),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: RollingNumber(key: ValueKey(live), value: balance, builder: (v) => Text(PlayMode.amount(v), style: AppText.number(34, color: live ? AppColors.text : AppColors.green))),
          ),
          if (!live) ...[
            const SizedBox(height: 4),
            Text(PlayMode.nairaEquivalent(balance), style: AppText.body(13, color: AppColors.textMuted)),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 20),
            for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(height: 10), actions[i]],
          ],
        ],
      ),
    );
  }
}
