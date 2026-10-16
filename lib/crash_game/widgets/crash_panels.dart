import 'package:flutter/material.dart';
import 'package:rev_game_mvp/components/components.dart';

/// Bottom panel while waiting for the next round.
class CrashBetPanel extends StatelessWidget {
  const CrashBetPanel({
    super.key,
    required this.bet,
    required this.minBet,
    required this.maxBet,
    required this.onBetChanged,
    required this.autoCashout,
    required this.autoTarget,
    required this.onAutoCashoutChanged,
    required this.onTargetChanged,
    required this.autoBet,
    required this.onAutoBetChanged,
    required this.onBet,
  });

  final double bet;
  final double minBet;
  final double maxBet;
  final ValueChanged<double> onBetChanged;

  final bool autoCashout;
  final double autoTarget;
  final ValueChanged<bool> onAutoCashoutChanged;
  final ValueChanged<double> onTargetChanged;

  final bool autoBet;
  final ValueChanged<bool> onAutoBetChanged;
  final VoidCallback onBet;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AmountField(label: 'Bet amount', value: bet, min: minBet, max: maxBet, onChanged: onBetChanged),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: StepperField(
                label: 'Auto cash out',
                valueText: '${autoTarget.toStringAsFixed(2)}x',
                active: autoCashout,
                onToggle: onAutoCashoutChanged,
                onMinus: () => onTargetChanged(autoTarget - 0.1),
                onPlus: () => onTargetChanged(autoTarget + 0.1),
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: PillChip(label: 'Auto bet', icon: Icons.autorenew_rounded, selected: autoBet, onTap: () => onAutoBetChanged(!autoBet)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        AppButton(label: 'BET', sublabel: formatCredits(bet), variant: AppButtonVariant.success, height: 64, onPressed: onBet),
      ],
    );
  }
}

/// Bottom panel while the round is live.
class CrashLivePanel extends StatelessWidget {
  const CrashLivePanel({
    super.key,
    required this.bet,
    required this.multiplier,
    required this.payout,
    required this.cashedOut,
    required this.onCashOut,
    this.autoTarget,
  });

  final double bet;
  final double multiplier;

  /// Payout locked in after cashing out.
  final double payout;
  final bool cashedOut;
  final VoidCallback onCashOut;

  /// Shown only when auto cash out is on.
  final double? autoTarget;

  @override
  Widget build(BuildContext context) {
    final live = (multiplier * 100).floorToDouble() / 100;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _kv('Your bet', formatCredits(bet)),
            if (autoTarget != null) _kv('Auto cash out', formatMultiplier(autoTarget!)),
          ],
        ),
        const SizedBox(height: 14),
        CashOutButton(
          label: cashedOut ? 'CASHED OUT' : 'CASH OUT',
          payout: cashedOut ? payout : bet * live,
          onPressed: cashedOut ? null : onCashOut,
        ),
        if (autoTarget != null) ...[
          const SizedBox(height: 14),
          AppProgressBar(value: (multiplier - 1) / (autoTarget! - 1), color: AppColors.green, height: 6),
        ],
        const SizedBox(height: 10),
        Text('Round is live. Server decides the crash point.', style: AppText.body(11, weight: FontWeight.w600, color: AppColors.textDim)),
      ],
    );
  }

  Widget _kv(String k, String v) => Text.rich(
        TextSpan(
          style: AppText.body(12, weight: FontWeight.w600, color: AppColors.textDim),
          children: [TextSpan(text: '$k  '), TextSpan(text: v, style: AppText.number(13))],
        ),
      );
}

/// Bottom panel after the crash.
class CrashResultPanel extends StatelessWidget {
  const CrashResultPanel({
    super.key,
    required this.bet,
    required this.payout,
    required this.cashedAt,
    required this.onVerify,
    required this.onNext,
    this.autoBet = false,
  });

  final double bet;
  final double payout;

  /// `null` when the player did not cash out in time.
  final double? cashedAt;
  final VoidCallback onVerify;
  final VoidCallback onNext;
  final bool autoBet;

  @override
  Widget build(BuildContext context) {
    final won = cashedAt != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        WinBanner(
          amount: won ? payout - bet : -bet,
          winLabel: 'CASHED OUT',
          lossLabel: 'CRASHED',
          caption: won ? 'at ${cashedAt!.toStringAsFixed(2)}x - you got out in time' : 'You did not cash out in time',
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: AppButton(label: 'Verify', variant: AppButtonVariant.outline, height: 56, onPressed: onVerify)),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: AppButton(
                label: autoBet ? 'NEXT ROUND...' : 'NEXT ROUND',
                variant: AppButtonVariant.success,
                height: 56,
                onPressed: onNext,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
