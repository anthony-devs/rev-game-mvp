import 'package:flutter/material.dart';

import '../buttons/app_button.dart';
import '../core/formatters.dart';

/// Gold Cash out button that shows the live payout.
///
/// ```dart
/// CashOutButton(payout: bet * multiplier, onPressed: cashOut)
/// ```
class CashOutButton extends StatelessWidget {
  const CashOutButton({super.key, required this.payout, required this.onPressed, this.label = 'CASH OUT'});

  final double payout;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      sublabel: formatCredits(payout),
      variant: AppButtonVariant.gold,
      height: 68,
      onPressed: onPressed,
    );
  }
}
