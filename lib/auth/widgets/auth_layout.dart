import 'package:flutter/material.dart';

import '../../components/components.dart';

/// Shared shell for every auth screen: glow background, back button, title,
/// scrollable body. Tapping outside a field closes the keyboard.
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.title, required this.subtitle, required this.children, this.showBack = true});

  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      glowColor: AppColors.purple,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 12, AppSpacing.xl, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    if (showBack && Navigator.of(context).canPop())
                      IconSquareButton(
                        icon: Icons.chevron_left_rounded,
                        semanticLabel: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                      )
                    else
                      Text('REV GAMES', style: AppText.heading(16, letterSpacing: -0.4)),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(title, style: AppText.heading(32, letterSpacing: -1.2)),
              const SizedBox(height: 8),
              Text(subtitle, style: AppText.body(15, color: AppColors.textMuted, height: 1.4)),
              const SizedBox(height: 28),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
