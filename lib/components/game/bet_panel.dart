import 'package:flutter/material.dart';

import '../buttons/app_button.dart';
import '../core/app_colors.dart';
import '../inputs/amount_field.dart';

/// Bottom sheet-like panel with amount field and the main action button.
///
/// ```dart
/// BetPanel(
///   bet: bet, onBetChanged: (v) => setState(() => bet = v),
///   minBet: 10, maxBet: balance,
///   actionLabel: 'BET', onAction: placeBet,
///   extra: SegmentedToggle<bool>(...),
/// )
/// ```
class BetPanel extends StatelessWidget {
  const BetPanel({
    super.key,
    required this.bet,
    required this.onBetChanged,
    required this.actionLabel,
    required this.onAction,
    this.minBet = 1,
    this.maxBet,
    this.actionVariant = AppButtonVariant.success,
    this.actionSublabel,
    this.busy = false,
    this.extra,
    this.betLabel = 'Bet amount',
  });

  final double bet;
  final ValueChanged<double> onBetChanged;
  final double minBet;
  final double? maxBet;
  final String betLabel;
  final String actionLabel;
  final String? actionSublabel;
  final AppButtonVariant actionVariant;

  /// `null` disables the action button.
  final VoidCallback? onAction;

  /// Shows a spinner in the action button and locks the amount.
  final bool busy;

  /// Optional controls placed above the amount field (toggle, chip picker...).
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: const BoxDecoration(
        color: AppColors.sheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (extra != null) ...[extra!, const SizedBox(height: 14)],
          AmountField(label: betLabel, value: bet, min: minBet, max: maxBet, enabled: !busy, onChanged: onBetChanged),
          const SizedBox(height: 14),
          AppButton(
            label: actionLabel,
            sublabel: actionSublabel,
            variant: actionVariant,
            height: 64,
            loading: busy,
            onPressed: onAction,
          ),
        ],
      ),
    );
  }
}
