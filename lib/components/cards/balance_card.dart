import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/formatters.dart';
import '../feedback/demo_badge.dart';

/// Big balance card for the Wallet screen. Put action buttons in [actions].
///
/// ```dart
/// BalanceCard(balance: 94250, actions: [AppButton(label: 'Get credits', onPressed: open)])
/// ```
class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key, required this.balance, this.label = 'Available credits', this.actions = const []});

  final double balance;
  final String label;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.lineStrong),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1F2A25), Color(0xFF121214)]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Text(label.toUpperCase(), style: AppText.label()), const SizedBox(width: 10), const DemoBadge()]),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(formatCredits(balance), style: AppText.number(34, color: AppColors.mint, shadows: AppText.glow(AppColors.mint, opacity: .35))),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 20),
            for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(height: 10), actions[i]],
          ],
        ],
      ),
    );
  }
}
