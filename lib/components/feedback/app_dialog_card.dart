import 'package:flutter/material.dart';

import '../buttons/app_button.dart';
import '../core/app_colors.dart';
import '../core/app_text.dart';

/// Centered dialog card (Reality check, confirmations).
///
/// ```dart
/// showAppDialog(context, AppDialogCard(
///   icon: Icons.schedule_rounded,
///   title: 'Time check',
///   message: 'You have been playing for 60 minutes.',
///   primaryLabel: 'Keep playing', onPrimary: () => Navigator.pop(context),
///   secondaryLabel: 'Take a break', onSecondary: leave,
/// ));
/// ```
Future<T?> showAppDialog<T>(BuildContext context, Widget card, {bool dismissible = false}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierColor: Colors.black.withValues(alpha: .7),
    builder: (_) => Center(child: Material(color: Colors.transparent, child: card)),
  );
}

class AppDialogCard extends StatelessWidget {
  const AppDialogCard({
    super.key,
    required this.title,
    required this.primaryLabel,
    required this.onPrimary,
    this.message,
    this.icon,
    this.iconColor,
    this.secondaryLabel,
    this.onSecondary,
    this.body,
  });

  final String title;
  final String? message;
  final IconData? icon;
  final Color? iconColor;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Extra content between the message and the buttons (e.g. session stats).
  final Widget? body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.sheet,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.lineStrong),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(shape: BoxShape.circle, color: (iconColor ?? AppColors.gold).withValues(alpha: .12), border: Border.all(color: (iconColor ?? AppColors.gold).withValues(alpha: .5))),
              child: Icon(icon, size: 30, color: (iconColor ?? AppColors.gold)),
            ),
            const SizedBox(height: 18),
          ],
          Text(title, textAlign: TextAlign.center, style: AppText.body(22, weight: FontWeight.w700)),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(message!, textAlign: TextAlign.center, style: AppText.body(14, color: AppColors.textMuted, height: 1.5)),
          ],
          if (body != null) ...[const SizedBox(height: 16), body!],
          const SizedBox(height: 24),
          AppButton(label: primaryLabel, onPressed: onPrimary),
          if (secondaryLabel != null) ...[
            const SizedBox(height: 10),
            AppButton(label: secondaryLabel!, onPressed: onSecondary, variant: AppButtonVariant.outline, height: 52),
          ],
        ],
      ),
    );
  }
}
