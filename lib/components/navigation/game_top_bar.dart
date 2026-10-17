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

  /// Turns the balance red when the player is nearly out of credits.
  final bool low;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          IconSquareButton(icon: Icons.chevron_left_rounded, iconSize: 26, semanticLabel: 'Back', onPressed: onBack),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(18, weight: FontWeight.w700),
            ),
          ),
          const RoundsPill(),
          const SizedBox(width: 8),
          BalancePill(balance: balance, low: low, compact: true),
          if (onVerify != null) ...[
            const SizedBox(width: 8),
            IconSquareButton(
              icon: Icons.verified_user_outlined,
              iconColor: AppColors.green,
              semanticLabel: 'Provably fair',
              onPressed: onVerify,
            ),
          ],
          for (final a in actions) ...[const SizedBox(width: 8), a],
        ],
      ),
    );
  }
}
