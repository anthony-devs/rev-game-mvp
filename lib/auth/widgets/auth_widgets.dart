import 'package:flutter/material.dart';

import '../../components/components.dart';

/// Red (error) or green (info) message above a form.
class AuthBanner extends StatelessWidget {
  const AuthBanner({super.key, this.error, this.info});

  final String? error;
  final String? info;

  @override
  Widget build(BuildContext context) {
    final text = error ?? info;
    if (text == null) return const SizedBox.shrink();
    final color = error != null ? AppColors.loss : AppColors.green;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(error != null ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppText.body(13, color: color, height: 1.35))),
        ],
      ),
    );
  }
}

/// "or continue with" divider.
class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final line = Expanded(child: Divider(height: 1, color: AppColors.line));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Row(
        children: [
          line,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(label, style: AppText.body(12, color: AppColors.textDim)),
          ),
          line,
        ],
      ),
    );
  }
}

/// "New here?  Create account" style text link.
class AuthLink extends StatelessWidget {
  const AuthLink({super.key, this.prefix, required this.action, required this.onTap, this.center = true});

  final String? prefix;
  final String action;
  final VoidCallback? onTap;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final child = PressScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text.rich(
          TextSpan(
            children: [
              if (prefix != null) TextSpan(text: '$prefix ', style: AppText.body(14, color: AppColors.textMuted)),
              TextSpan(text: action, style: AppText.body(14, weight: FontWeight.w700, color: AppColors.gold)),
            ],
          ),
        ),
      ),
    );
    return center ? Center(child: child) : Align(alignment: Alignment.centerRight, child: child);
  }
}

/// Eye icon that shows or hides a password.
class PasswordToggle extends StatelessWidget {
  const PasswordToggle({super.key, required this.obscured, required this.onTap});

  final bool obscured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: obscured ? 'Show password' : 'Hide password',
      icon: Icon(obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: AppColors.textDim),
    );
  }
}
