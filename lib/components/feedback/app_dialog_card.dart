import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../buttons/app_button.dart';
import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../../core/open_guard.dart';

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
  final label = card is AppDialogCard ? card.title : '';
  if (!OpenGuard.allow('dialog:${card.runtimeType}:$label')) return Future<T?>.value(null);
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
    final media = MediaQuery.sizeOf(context);
    // Never wider than the screen (small phones) and never taller than it (short/landscape/folded):
    // the card fits the width available and scrolls inside if the content is tall.
    return Container(
      width: math.min(340, media.width - 48),
      constraints: BoxConstraints(maxHeight: media.height - 48),
      padding: const EdgeInsets.all(22),
      // A purple-tinted card with a purple edge, like a promo card (flat colour, no gradient).
      decoration: BoxDecoration(
        color: Color.alphaBlend(AppColors.purple.withValues(alpha: .10), AppColors.sheet),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.purple.withValues(alpha: .55), width: 1.2),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          // Text on the left, the icon on the right (where a promo card puts its picture).
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title.toUpperCase(), style: AppText.heading(21, letterSpacing: .2, height: 1.15)),
                    if (message != null) ...[
                      const SizedBox(height: 8),
                      Text(message!, style: AppText.body(14, color: AppColors.textMuted, height: 1.5)),
                    ],
                  ],
                ),
              ),
              if (icon != null) ...[
                const SizedBox(width: 14),
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: (iconColor ?? AppColors.gold).withValues(alpha: .14)),
                  child: Icon(icon, size: 34, color: iconColor ?? AppColors.gold),
                ),
              ],
            ],
          ),
          if (body != null) ...[const SizedBox(height: 16), body!],
          const SizedBox(height: 22),
          AppButton(label: primaryLabel, onPressed: onPrimary),
          if (secondaryLabel != null) ...[
            const SizedBox(height: 10),
            AppButton(label: secondaryLabel!, onPressed: onSecondary, variant: AppButtonVariant.outline, height: 48, fontSize: 14),
          ],
          ],
        ),
      ),
    );
  }
}
