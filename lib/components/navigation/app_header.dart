import 'package:flutter/material.dart';

import '../core/app_text.dart';
import '../../rounds/rounds_pill.dart';
import '../feedback/balance_pill.dart';
import '../feedback/coach_tour.dart';

/// Lobby header: wordmark + balance pill.
///
/// ```dart
/// AppHeader(title: 'REV GAMES', balance: 94250, onBalanceTap: openWallet, onAdd: openGetCredits)
/// ```
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.balance,
    this.title = 'REV GAMES',
    this.onBalanceTap,
    this.onAdd,
    this.dropdown = false,
    this.action,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 12),
  });

  final String title;
  final double balance;
  final VoidCallback? onBalanceTap;

  /// Shows the white plus badge when set.
  final VoidCallback? onAdd;

  /// Balance pill shows a chevron (opens the wallet picker).
  final bool dropdown;

  /// Optional widget between the title and the balance (e.g. the support button).
  final Widget? action;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            flex: 2,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(title, maxLines: 1, style: AppText.heading(30, letterSpacing: -1.5)),
            ),
          ),
          const SizedBox(width: 10),
          // Support, rounds and balance shrink together when the screen is narrow, the font is large
          // or the balance is long, instead of overflowing the row.
          Flexible(
            flex: 3,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (action != null) ...[CoachTarget(id: 'support', child: action!), const SizedBox(width: 8)],
                  const CoachTarget(id: 'rounds', child: RoundsPill()),
                  const SizedBox(width: 8),
                  CoachTarget(id: 'balance', child: BalancePill(balance: balance, onTap: onBalanceTap, onAdd: onAdd, dropdown: dropdown)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
