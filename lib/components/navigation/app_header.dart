import 'package:flutter/material.dart';

import '../core/app_text.dart';
import '../feedback/balance_pill.dart';

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
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 12),
  });

  final String title;
  final double balance;
  final VoidCallback? onBalanceTap;

  /// Shows the white plus badge when set.
  final VoidCallback? onAdd;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.heading(30, letterSpacing: -1.5))),
          const SizedBox(width: 12),
          BalancePill(balance: balance, onTap: onBalanceTap, onAdd: onAdd),
        ],
      ),
    );
  }
}
