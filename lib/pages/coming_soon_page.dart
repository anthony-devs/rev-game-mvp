import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../catalog/upcoming.dart';
import '../components/components.dart';
import '../games/game_support.dart' show showToast;
import '../model/model.dart';
import '../user/bloc/profile_cubit.dart';

/// A game that isn't out yet: hero artwork, what to expect, and a waitlist. When the game
/// launches the lobby marks it NEW for everyone on the list.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({super.key, required this.game});

  final GameInfo game;

  @override
  Widget build(BuildContext context) {
    final info = upcomingInfoFor(game);
    final slug = slugOf(game.id);
    final joined = context.select((ProfileCubit c) => c.state.settings.waitlist.contains(slug));
    final accent = info.accent;

    void toggle() {
      final cubit = context.read<ProfileCubit>();
      final s = cubit.state.settings;
      final next = joined ? [for (final w in s.waitlist) if (w != slug) w] : [...s.waitlist, slug];
      AppHaptics.selection();
      cubit.updateSettings(s.copyWith(waitlist: next));
      showToast(context, joined ? 'Removed from the waitlist' : "You're on the waitlist. We'll mark ${game.name} NEW in your lobby when it's live.");
    }

    return AppScaffold(
      glowColor: accent,
      body: Column(
        children: [
          SubPageBar(title: game.name, onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: SizedBox(
                    height: 230,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        GameArt(kind: info.kind, borderRadius: 0),
                        ColoredBox(color: AppColors.bg.withValues(alpha: .55)),
                        const Positioned(top: 14, left: 14, child: StatusPill(label: 'COMING SOON', pulsing: true)),
                        Positioned(
                          left: 18,
                          right: 18,
                          bottom: 16,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(game.tag.toUpperCase(), style: AppText.label(color: accent)),
                              const SizedBox(height: 4),
                              Text(game.name, style: AppText.body(28, weight: FontWeight.w800, height: 1.1)),
                              const SizedBox(height: 4),
                              Text(info.tagline, style: AppText.body(14, color: AppColors.textSoft)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('What to expect', style: AppText.body(16, weight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(info.about, style: AppText.body(14, color: AppColors.textMuted, height: 1.55)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in info.features)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(20), border: Border.all(color: accent.withValues(alpha: .4))),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_rounded, size: 15, color: accent),
                            const SizedBox(width: 6),
                            Text(f, style: AppText.body(12, weight: FontWeight.w600)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 26),
                AppButton(
                  label: joined ? 'ON THE WAITLIST' : 'JOIN THE WAITLIST',
                  variant: joined ? AppButtonVariant.outline : AppButtonVariant.primary,
                  icon: joined ? Icons.check_circle_rounded : Icons.notifications_none_rounded,
                  onPressed: toggle,
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    joined ? 'Tap again to leave the list.' : "We'll mark it NEW in your lobby the moment it's live.",
                    textAlign: TextAlign.center,
                    style: AppText.body(12, color: AppColors.textDim),
                  ),
                ),
                const SizedBox(height: 16),
                AppButton(label: 'Back to lobby', variant: AppButtonVariant.outline, height: 52, onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
