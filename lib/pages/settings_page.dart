import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../games/game_support.dart';
import '../user/bloc/profile_cubit.dart';
import '../user/pages/profile_page.dart';
import '../legal/legal_page.dart';
import 'help_page.dart';
import 'history_page.dart';
import 'limits_page.dart';
import 'round_format.dart';
import 'wallet_page.dart';
import '../support/support_button.dart';
import '../theme/theme_cubit.dart';

/// U1. Settings tab. Sign out lives in the profile, not here.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.select((ProfileCubit c) => c.state.user);
    final progress = context.select((ProfileCubit c) => c.state.progress);
    final settings = context.select((ProfileCubit c) => c.state.settings);
    final cubit = context.read<ProfileCubit>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 8, AppSpacing.screen, 120),
      children: [
        Text('Settings', style: AppText.heading(28, letterSpacing: -1)),
        const SizedBox(height: 16),
        PressScale(
          onTap: () => pushPage<void>(context, const ProfilePage()),
          scale: .99,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.line)),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.purple.withValues(alpha: .18), shape: BoxShape.circle, border: Border.all(color: AppColors.purple.withValues(alpha: .6))),
                  child: Text(user.initial, style: AppText.heading(20, color: AppColors.purple, letterSpacing: 0)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.isAnonymous ? 'Guest player' : user.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(16, weight: FontWeight.w700)),
                      Text('Level ${progress.level} · ${levelTitle(progress.level)}', style: AppText.body(12, color: AppColors.textDim)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        ListGroup(
          title: 'Appearance',
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: BlocBuilder<ThemeCubit, ThemeState>(
                builder: (context, theme) => SegmentedToggle<ThemeMode>(
                  height: 44,
                  options: const [
                    SegmentOption(value: ThemeMode.system, label: 'System'),
                    SegmentOption(value: ThemeMode.light, label: 'Light'),
                    SegmentOption(value: ThemeMode.dark, label: 'Dark'),
                  ],
                  selected: theme.mode,
                  onChanged: (m) => context.read<ThemeCubit>().setMode(m),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        ListGroup(
          title: 'Gameplay',
          children: [
            SwitchRow(
              title: 'Sound effects',
              value: settings.soundEnabled,
              onChanged: (v) {
                cubit.updateSettings(settings.copyWith(soundEnabled: v));
                if (v) AppSound.play(Sfx.chip);
              },
            ),
            SwitchRow(
              title: 'Game music',
              subtitle: 'Each game has its own background track',
              value: settings.musicEnabled,
              onChanged: (v) => cubit.updateSettings(settings.copyWith(musicEnabled: v)),
            ),
            SwitchRow(title: 'Haptics', value: settings.hapticsEnabled, onChanged: (v) => cubit.updateSettings(settings.copyWith(hapticsEnabled: v))),
            SwitchRow(title: 'Turbo spin', subtitle: 'Faster spins in Slots', value: settings.turboByDefault, onChanged: (v) => cubit.updateSettings(settings.copyWith(turboByDefault: v))),
          ],
        ),
        const SizedBox(height: 22),
        ListGroup(
          title: 'Account and safety',
          children: [
            ListRowTile(icon: Icons.account_balance_wallet_outlined, title: 'Wallet and credits', onTap: () => pushPage<void>(context, const WalletPage())),
            ListRowTile(icon: Icons.shield_outlined, title: 'Play limits and breaks', onTap: () => pushPage<void>(context, const LimitsPage())),
            ListRowTile(icon: Icons.history_rounded, title: 'Game history', onTap: () => pushPage<void>(context, const HistoryPage())),
            ListRowTile(icon: Icons.help_outline_rounded, title: 'Help Centre', trailing: const SupportBadge(), onTap: () => pushPage<void>(context, const HelpPage())),
            ListRowTile(icon: Icons.gavel_rounded, title: 'Legal and policies', onTap: () => pushPage<void>(context, const LegalPage())),
            const ListRowTile(icon: Icons.language_rounded, title: 'Language', trailingText: 'English', showChevron: false),
          ],
        ),
        const SizedBox(height: 24),
        Center(child: Text('Demo build 1.0.0 · Virtual credits only', style: AppText.body(12, color: AppColors.textFaint))),
      ],
    );
  }
}
