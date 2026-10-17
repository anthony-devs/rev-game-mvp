import 'package:flutter/material.dart';

import '../components/components.dart';
import '../slots_game/slots_models.dart';
import '../slots_game/slots_theme.dart';
import '../slots_game/symbol_view.dart';

/// Slots paytable and rules. A full page with a back button, so leaving it is easy.
class PaytablePage extends StatelessWidget {
  const PaytablePage({super.key, required this.cfg});

  final SlotsConfig cfg;

  @override
  Widget build(BuildContext context) {
    Widget stat(String k, String v) => Expanded(child: StatTile(label: k, value: v));
    return AppScaffold(
      glowColor: AppColors.purple,
      body: Column(
        children: [
          SubPageBar(title: 'Paytable & rules', onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 8, AppSpacing.screen, 24),
              children: [
                Text('PAYOUTS · MATCH ON THE PAYLINE', style: AppText.label()),
                const SizedBox(height: 10),
                for (final row in cfg.payRows) ...[
                  Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(children: [
                      SizedBox(
                        width: 112,
                        child: Row(children: [
                          for (final s in row.symbols) ...[SymbolView(s, size: 30), const SizedBox(width: 4)],
                        ]),
                      ),
                      Expanded(child: Text(row.label, style: AppText.body(14, weight: FontWeight.w600, color: AppColors.textSoft))),
                      Text('×${row.multiplier}', style: AppText.number(17, color: AppColors.gold)),
                    ]),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 14),
                Text('HOW TO PLAY', style: AppText.label()),
                const SizedBox(height: 8),
                Text(
                  'Set your bet, then press SPIN. Three matching symbols on the payline pay your bet times the multiplier. '
                  'Any two cherries pay ×2. The server decides every result before the reels stop, and you can check any spin in Provably fair.',
                  style: AppText.body(14, weight: FontWeight.w400, color: AppColors.textSoft, height: 1.5),
                ),
                const SizedBox(height: 18),
                Row(children: [stat('Min bet', fmt(cfg.minBet)), const SizedBox(width: 8), stat('Max bet', fmt(cfg.maxBet))]),
                const SizedBox(height: 8),
                Row(children: [stat('Max win', fmt(cfg.maxWin)), const SizedBox(width: 8), stat('Return to player', '${(cfg.rtp * 100).round()}%')]),
                const SizedBox(height: 14),
                Text('Payouts shown are the current values for this game.', style: AppText.body(11, weight: FontWeight.w400, color: AppColors.textDim)),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).padding.bottom),
            child: AppButton(label: 'Back to game', variant: AppButtonVariant.outline, onPressed: () => Navigator.of(context).maybePop()),
          ),
        ],
      ),
    );
  }
}
