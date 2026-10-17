import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../buttons/icon_square_button.dart';

import '../core/app_colors.dart';
import '../core/responsive.dart';
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
    this.onHelp,
    this.lowBalance = false,
    this.glowColor,
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

  /// Shows a ? button that opens the how-to-play guide.
  final VoidCallback? onHelp;
  
  /// Kept for compatibility; game screens are flat now.
  final Color? glowColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppColors.light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
        child: SafeArea(
          child: LayoutBuilder(builder: (context, box) {
            final twoPane = panel != null && box.maxWidth >= Breakpoints.twoPane;
            final top = GameTopBar(title: title, balance: balance, low: lowBalance, onBack: onBack ?? () => Navigator.maybePop(context), onVerify: onVerify, actions: [if (onHelp != null) IconSquareButton(icon: Icons.help_outline_rounded, semanticLabel: 'How to play', onPressed: onHelp)]);
            if (twoPane) {
              // iPad landscape, Mac, browser: the table on the left, the controls beside it.
              return Column(
                children: [
                  ContentWidth(maxWidth: 1280, child: top),
                  if (banner != null) banner!,
                  Expanded(
                    child: ContentWidth(
                      maxWidth: 1280,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: ContentWidth(maxWidth: 760, child: stage)),
                          SizedBox(
                            width: 400,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, 4, 16, 16),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(28),
                                child: ColoredBox(
                                  color: AppColors.sheet,
                                  child: SingleChildScrollView(child: panel!),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }
            // Phone, or an iPad held upright: one column, kept to a comfortable width.
            return ContentWidth(
              maxWidth: 640,
              child: Column(
                children: [
                  top,
                  if (banner != null) banner!,
                  Expanded(child: stage),
                  if (panel != null) panel!,
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}
