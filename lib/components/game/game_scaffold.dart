import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../navigation/game_top_bar.dart';

/// Standard layout for a game screen: top bar, stage, bet panel.
///
/// ```dart
/// GameScaffold(
///   title: 'Roulette', balance: balance, glowColor: AppColors.green,
///   onBack: () => Navigator.pop(context), onVerify: openFairness,
///   stage: RouletteWheel(...), panel: BetPanel(...),
/// )
/// ```
class GameScaffold extends StatelessWidget {
  const GameScaffold({
    super.key,
    required this.title,
    required this.balance,
    required this.stage,
    this.panel,
    this.onBack,
    this.onVerify,
    this.lowBalance = false,
    this.glowColor = AppColors.green,
    this.banner,
  });

  final String title;
  final double balance;
  final bool lowBalance;
  final Widget stage;

  /// Bottom controls (usually a `BetPanel`).
  final Widget? panel;

  /// Optional strip under the top bar (e.g. `HistoryStrip`).
  final Widget? banner;
  final VoidCallback? onBack;
  final VoidCallback? onVerify;
  final Color glowColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(center: const Alignment(0, -.3), radius: 1.1, colors: [glowColor.withValues(alpha: .14), AppColors.bg]),
        ),
        child: SafeArea(
          child: Column(
            children: [
              GameTopBar(title: title, balance: balance, low: lowBalance, onBack: onBack ?? () => Navigator.maybePop(context), onVerify: onVerify),
              if (banner != null) banner!,
              Expanded(child: stage),
              if (panel != null) panel!,
            ],
          ),
        ),
      ),
    );
  }
}
