import 'package:flutter/material.dart';

import '../components/components.dart';

/// Stands in for the payment provider's own page (Paystack, Stripe...) while the real
/// accounts don't exist yet. Returns `true` paid, `false` declined, `null` closed.
Future<bool?> showMockGateway(BuildContext context, {required String provider, required double amount, required bool deposit}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: .75),
    builder: (ctx) => Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: AppColors.lineStrong)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DemoBadge(label: 'MOCK GATEWAY · NO REAL MONEY', color: AppColors.blue, fontSize: 9),
              const SizedBox(height: 16),
              Text(provider, style: AppText.body(20, weight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(deposit ? 'Pay' : 'Send', style: AppText.body(13, color: AppColors.textDim)),
              const SizedBox(height: 6),
              Text(PlayMode.money(amount), style: AppText.number(30)),
              const SizedBox(height: 20),
              AppButton(label: 'Authorise payment', variant: AppButtonVariant.gold, onPressed: () => Navigator.of(ctx).pop(true)),
              const SizedBox(height: 10),
              AppButton(label: 'Decline', variant: AppButtonVariant.outline, height: 48, onPressed: () => Navigator.of(ctx).pop(false)),
              const SizedBox(height: 4),
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Close without paying', style: AppText.body(12, color: AppColors.textDim))),
            ],
          ),
        ),
      ),
    ),
  );
}
