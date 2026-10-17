import 'package:flutter/material.dart';

import '../buttons/app_button.dart';
import '../core/app_colors.dart';
import '../core/app_text.dart';

/// Full-screen message: offline, maintenance, empty list, error.
///
/// ```dart
/// StatusView.offline(onRetry: reload)
/// StatusView.maintenance(message: 'Back at 14:00')
/// StatusView(icon: Icons.history_rounded, title: 'No rounds yet', message: 'Play a game to see it here.')
/// ```
class StatusView extends StatelessWidget {
  const StatusView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.color,
  });

  factory StatusView.offline({Key? key, VoidCallback? onRetry}) => StatusView(
        key: key,
        icon: Icons.wifi_off_rounded,
        title: 'You are offline',
        message: 'Check your connection and try again. Your credits are safe.',
        actionLabel: onRetry == null ? null : 'Try again',
        onAction: onRetry,
      );

  factory StatusView.maintenance({Key? key, String message = 'We are making things better. Please check back soon.'}) =>
      StatusView(key: key, icon: Icons.build_circle_outlined, title: 'Under maintenance', message: message, color: AppColors.gold);

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (color ?? AppColors.textMuted).withValues(alpha: .1),
                border: Border.all(color: (color ?? AppColors.textMuted).withValues(alpha: .4)),
              ),
              child: Icon(icon, size: 44, color: (color ?? AppColors.textMuted)),
            ),
            const SizedBox(height: 24),
            Text(title, textAlign: TextAlign.center, style: AppText.body(22, weight: FontWeight.w700)),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!, textAlign: TextAlign.center, style: AppText.body(14, color: AppColors.textDim, height: 1.5)),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 28),
              AppButton(label: actionLabel!, onPressed: onAction, expanded: false),
            ],
          ],
        ),
      ),
    );
  }
}
