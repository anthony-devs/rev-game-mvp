import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/formatters.dart';
import '../core/press_scale.dart';

/// One round in History / Wallet activity.
///
/// ```dart
/// ActivityRow(game: 'Golden Reels', detail: 'Bet 100, 3 min ago', amount: 450, onTap: openRound)
/// ```
class ActivityRow extends StatelessWidget {
  const ActivityRow({super.key, required this.game, required this.amount, this.detail, this.icon = Icons.casino_outlined, this.onTap});

  final String game;
  final String? detail;

  /// Net result in credits. Positive = green, negative = red.
  final double amount;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = amount > 0 ? AppColors.green : (amount < 0 ? AppColors.loss : AppColors.textMuted);
    return PressScale(
      onTap: onTap,
      scale: .99,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: AppColors.handle.withValues(alpha: .6), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 20, color: AppColors.textSoft),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(game, style: AppText.body(15, weight: FontWeight.w600)),
                  if (detail != null) Text(detail!, style: AppText.body(12, color: AppColors.textDim)),
                ],
              ),
            ),
            Text(formatSigned(amount), style: AppText.number(15, color: c)),
          ],
        ),
      ),
    );
  }
}
