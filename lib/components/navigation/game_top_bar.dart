import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../buttons/icon_square_button.dart';
import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../../rounds/rounds_pill.dart';
import '../feedback/balance_pill.dart';

/// Top bar inside every game: back, title, balance, fairness shield.
///
/// ```dart
/// GameTopBar(title: 'Roulette', balance: balance, onBack: () => Navigator.pop(context), onVerify: openFairness)
/// ```
class GameTopBar extends StatelessWidget {
  const GameTopBar({
    super.key,
    required this.title,
    required this.balance,
    this.onBack,
    this.onVerify,
    this.low = false,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 8),
  });

  final String title;
  final double balance;
  final VoidCallback? onBack;
  final VoidCallback? onVerify;

  /// Extra buttons shown after the shield (sound, info...).
  final List<Widget> actions;

  /// Turns the balance red when the player is nearly out of coins.
  final bool low;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: LayoutBuilder(builder: (context, box) {
        // On a phone the bar is crowded: tighter gaps and a smaller title keep everything on one line.
        final narrow = box.maxWidth < 420;
        final gap = SizedBox(width: narrow ? 6 : 8);
        final gapW = narrow ? 6.0 : 8.0;
        // Width the buttons take (44 each) so the pills only get what is left. The title keeps a small
        // minimum and the pills shrink to fit, so the row can never overflow on a small phone or a big font.
        final buttons = 1 + (onVerify != null ? 1 : 0) + actions.length;
        final fixed = buttons * 44.0 + (narrow ? 8 : 12) + gapW * buttons + gapW;
        const titleMin = 64.0;
        final pillBudget = math.max(72.0, box.maxWidth - fixed - titleMin);
        return Row(
          children: [
            IconSquareButton(icon: Icons.chevron_left_rounded, iconSize: 26, semanticLabel: 'Back', onPressed: onBack),
            SizedBox(width: narrow ? 8 : 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(narrow ? 16 : 18, weight: FontWeight.w700),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: pillBudget),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RoundsPill(compact: narrow),
                    gap,
                    BalancePill(balance: balance, low: low, compact: true),
                  ],
                ),
              ),
            ),
            if (onVerify != null) ...[
              gap,
              IconSquareButton(
                icon: Icons.verified_user_outlined,
                iconColor: AppColors.green,
                semanticLabel: 'Provably fair',
                onPressed: onVerify,
              ),
            ],
            for (final a in actions) ...[gap, a],
          ],
        );
      }),
    );
  }
}
