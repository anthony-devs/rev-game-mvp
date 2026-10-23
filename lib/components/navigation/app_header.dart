import 'package:flutter/material.dart';

import '../core/app_text.dart';
import '../../rounds/rounds_pill.dart';
import '../feedback/balance_pill.dart';
import '../feedback/coach_tour.dart';
import '../feedback/rev_mark.dart';

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
    // Two rows: the name on the first, and the support, rounds and balance controls on the second, at the
    // right and at their normal size. (On one row they were squeezed small next to the name.) The row only
    // scales down when the balance is so long that it would not fit the screen.
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: title == 'REV GAMES' ? const RevWordmark() : Text(title, maxLines: 1, style: AppText.heading(20, letterSpacing: -.4)),
          ),
          const SizedBox(height: 12),
          FittedBox(
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
        ],
      ),
    );
  }
}
