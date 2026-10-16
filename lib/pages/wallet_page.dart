import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../games/game_support.dart';
import '../model/model.dart';
import '../user/bloc/profile_cubit.dart';
import '../user/data/user_repository.dart';
import 'fairness_page.dart';
import 'get_credits_sheet.dart';
import 'history_page.dart';
import 'round_format.dart';

/// W1. Balance, level, stats and the latest rounds.
class WalletPage extends StatelessWidget {
  const WalletPage({super.key});

  @override
  Widget build(BuildContext context) {
    final balance = watchBalance(context);
    final ready = context.select((ProfileCubit c) => c.state.walletReady);
    final progress = context.select((ProfileCubit c) => c.state.progress);
    final uid = context.select((ProfileCubit c) => c.state.user.id);

    return AppScaffold(
      glowColor: AppColors.green,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, 32),
        children: [
          SubPageBar(title: 'Wallet', onBack: () => Navigator.of(context).maybePop(), padding: const EdgeInsets.symmetric(vertical: 8)),
          const SizedBox(height: 8),
          if (ready)
            BalanceCard(
              balance: balance,
              label: 'Credits',
              actions: [
                AppButton(label: 'Get demo credits', variant: AppButtonVariant.gold, height: 50, fontSize: 15, onPressed: () => showGetCredits(context)),
              ],
            )
          else
            const SkeletonBox(height: 172, radius: 24),
          const SizedBox(height: 6),
          Center(child: Text('Virtual credits. No cash value.', style: AppText.body(12, color: AppColors.textDim))),
          const SizedBox(height: 16),
          LevelProgressCard(
            level: progress.level,
            title: levelTitle(progress.level),
            xp: progress.xp,
            xpMax: progress.xpForNext,
            streakDays: progress.streakDays,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: StatTile(label: 'Rounds', value: formatCredits(progress.totalRounds, decimals: 0))),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  label: 'Best win',
                  value: progress.bestMultiplier <= 0 ? '-' : formatMultiplier(progress.bestMultiplier, trim: true),
                  valueColor: AppColors.gold,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: StatTile(label: 'Win rate', value: '${(progress.winRate * 100).round()}%')),
            ],
          ),
          const SizedBox(height: 24),
          SectionHeader(
            title: 'Recent activity',
            padding: EdgeInsets.zero,
            actionLabel: 'View All',
            onAction: () => pushPage<void>(context, const HistoryPage()),
          ),
          const SizedBox(height: 10),
          if (uid.isNotEmpty) _Recent(uid: uid),
        ],
      ),
    );
  }
}

class _Recent extends StatelessWidget {
  const _Recent({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GameRound>>(
      stream: context.read<UserRepository>().watchRounds(uid, limit: 4),
      builder: (context, snap) {
        if (snap.hasError) {
          return const InfoCard(message: 'Could not load your activity. It will appear when you are back online.', icon: Icons.wifi_off_rounded, color: AppColors.textDim);
        }
        if (!snap.hasData) {
          return const Column(children: [SkeletonBox(height: 62, radius: 16), SizedBox(height: 8), SkeletonBox(height: 62, radius: 16)]);
        }
        final rounds = snap.data!;
        if (rounds.isEmpty) {
          return const InfoCard(title: 'No rounds yet', message: 'Play a game and your results will show up here.');
        }
        return ListGroup(
          children: [
            for (final r in rounds)
              ActivityRow(
                game: r.game.title,
                detail: r.summary,
                amount: r.net,
                icon: r.game.icon,
                onTap: () => pushPage<void>(context, FairnessPage(roundId: r.id)),
              ),
          ],
        );
      },
    );
  }
}
