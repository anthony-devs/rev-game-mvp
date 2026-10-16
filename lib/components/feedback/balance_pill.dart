import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/formatters.dart';
import '../core/press_scale.dart';

/// Outlined pill showing the DEMO balance.
///
/// ```dart
/// BalancePill(balance: 94250, onTap: openWallet, onAdd: openGetCredits)
/// BalancePill(balance: 12, compact: true, low: true)
/// ```
class BalancePill extends StatelessWidget {
  const BalancePill({
    super.key,
    required this.balance,
    this.onTap,
    this.onAdd,
    this.compact = false,
    this.low = false,
    this.tag = 'DEMO',
    this.decimals = 2,
  });

  final double balance;
  final VoidCallback? onTap;

  /// Shows a white plus badge on the right.
  final VoidCallback? onAdd;

  /// Hides the tag and shrinks the text. Used in game bars.
  final bool compact;
  final bool low;

  /// Small gold label. Set to `null` to hide.
  final String? tag;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final color = low ? AppColors.loss : AppColors.mint;
    return PressScale(
      onTap: onTap,
      child: Container(
        height: compact ? 40 : 46,
        padding: EdgeInsets.only(left: compact ? 12 : 14, right: onAdd != null ? 5 : (compact ? 12 : 14)),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(46),
          border: Border.all(color: AppColors.lineStrong, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!compact && tag != null) ...[
              Text(tag!, style: AppText.body(10, weight: FontWeight.w800, color: AppColors.gold, letterSpacing: 1)),
              const SizedBox(width: 8),
            ],
            Text(formatCredits(balance, decimals: decimals), style: AppText.number(compact ? 13 : 15, color: color)),
            if (onAdd != null) ...[
              const SizedBox(width: 10),
              PressScale(
                onTap: onAdd,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.add_rounded, size: 22, color: AppColors.bg),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
