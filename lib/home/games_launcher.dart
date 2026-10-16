import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../auth/bloc/auth_bloc.dart';
import '../components/components.dart';
import '../crash_game/crash_page.dart';
import '../slots_game/slots_page.dart';

/// Temporary lobby so you can open each game while the real lobby is built.
class GamesLauncher extends StatelessWidget {
  const GamesLauncher({super.key});

  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      glowColor: AppColors.purple,
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screen),
        children: [
          const _AccountBar(),
          const SizedBox(height: 24),
          Text('REV GAMES', style: AppText.heading(30, letterSpacing: -1.5)),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              GameTile(title: 'Golden Reels', tag: 'Slots', kind: GameKind.slots, onTap: () => _open(context, const SlotsPage())),
              GameTile(title: 'Dash Crash', tag: 'Instant', kind: GameKind.crash, onTap: () => _open(context, const CrashPage())),
            ],
          ),
        ],
      ),
    );
  }
}

/// Who is playing, with a sign out button.
class _AccountBar extends StatelessWidget {
  const _AccountBar();

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthBloc b) => b.state.user);
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.line),
          ),
          child: Text(user.initial, style: AppText.heading(18, color: AppColors.gold, letterSpacing: 0)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(15, weight: FontWeight.w700)),
              Text(
                user.isAnonymous ? 'Guest' : (user.email ?? 'Signed in'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(12, color: AppColors.textDim),
              ),
            ],
          ),
        ),
        IconSquareButton(
          icon: Icons.logout_rounded,
          semanticLabel: 'Sign out',
          onPressed: () => context.read<AuthBloc>().add(const AuthSignOutRequested()),
        ),
      ],
    );
  }
}
