import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../games/game_support.dart';
import '../user/bloc/profile_cubit.dart';
import '../user/data/daily_rewards.dart';
import '../user/data/user_repository.dart';

/// W2. Free demo coins: the daily streak reward and a reset.
Future<void> showGetCredits(BuildContext context) {
  return showAppBottomSheet<void>(context, child: const _GetCredits());
}

class _GetCredits extends StatefulWidget {
  const _GetCredits();

  @override
  State<_GetCredits> createState() => _GetCreditsState();
}

class _GetCreditsState extends State<_GetCredits> {
  Timer? _tick;
  bool _claiming = false;
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _claim() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    try {
      final claim = await context.read<ProfileCubit>().claimDaily();
      AppSound.play(Sfx.coin);
      AppHaptics.medium();
      if (mounted) showToast(context, '+${formatCredits(claim.claimed, decimals: 0)} coins added');
    } catch (e) {
      AppSound.play(Sfx.error);
      if (mounted) showToast(context, ProfileCubit.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  Future<void> _reset() async {
    final ok = await showAppDialog<bool>(
      context,
      AppDialogCard(
        icon: Icons.restart_alt_rounded,
        title: 'Reset your coins?',
        message: 'Your balance goes back to ${formatCredits(UserRepository.startingBalance, decimals: 0)}. Your history and level stay.',
        primaryLabel: 'Reset',
        onPrimary: () => Navigator.of(context).pop(true),
        secondaryLabel: 'Cancel',
        onSecondary: () => Navigator.of(context).pop(false),
      ),
      dismissible: true,
    );
    if (ok != true || !mounted) return;
    setState(() => _resetting = true);
    try {
      await context.read<ProfileCubit>().resetBalance();
      AppSound.play(Sfx.coin);
      if (mounted) {
        showToast(context, 'Coins reset to ${formatCredits(UserRepository.startingBalance, decimals: 0)}');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) showToast(context, ProfileCubit.errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.select((ProfileCubit c) => c.state.wallet);
    final progress = context.select((ProfileCubit c) => c.state.progress);
    final ready = context.select((ProfileCubit c) => c.state.walletReady);
    final now = DateTime.now();
    final daily = previewDaily(wallet, progress, now);
    final claimed = claimedDotsToday(wallet, progress, now);
    final streak = progress.streakDays;
    final live = wallet.lastDailyClaimAt != null && now.difference(wallet.lastDailyClaimAt!) <= kStreakGrace ? streak : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Get free coins', style: AppText.body(20, weight: FontWeight.w700))),
            IconSquareButton(icon: Icons.close_rounded, semanticLabel: 'Close', onPressed: () => Navigator.of(context).pop()),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.gold.withValues(alpha: .4)),
            color: AppColors.gold.withValues(alpha: .1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DAILY REWARD  ·  DAY ${daily.day}', style: AppText.label(color: AppColors.gold)),
              const SizedBox(height: 6),
              Text('+${formatCredits(daily.amount, decimals: 0)} coins', style: AppText.number(26, color: AppColors.gold)),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (var i = 1; i <= kDailyRewards.length; i++) ...[
                    if (i > 1) const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        children: [
                          Container(
                            height: 8,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: i <= claimed ? AppColors.gold : (i == daily.day && daily.ready ? AppColors.gold.withValues(alpha: .35) : AppColors.track),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (kDailyRewards[i - 1] >= 1000 ? '${(kDailyRewards[i - 1] / 1000).toStringAsFixed(kDailyRewards[i - 1] % 1000 == 0 ? 0 : 1)}K' : '${kDailyRewards[i - 1]}'),
                            style: AppText.body(9, weight: FontWeight.w700, color: i == daily.day ? AppColors.gold : AppColors.textFaint, height: 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppButton(
          label: !ready
              ? 'Loading'
              : (daily.ready ? 'Claim reward' : 'Next reward in ${formatCountdown(daily.secondsLeft)}'),
          variant: AppButtonVariant.gold,
          loading: _claiming,
          onPressed: (!ready || !daily.ready || _claiming) ? null : _claim,
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            live > 0 ? '$live day streak. Day 7 pays ${formatCredits(kDailyRewards.last, decimals: 0)}.' : 'Claim every day to build a streak. Day 7 pays ${formatCredits(kDailyRewards.last, decimals: 0)}.',
            textAlign: TextAlign.center,
            style: AppText.body(12, color: AppColors.textDim),
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.line)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Reset to ${formatCredits(UserRepository.startingBalance, decimals: 0)}', style: AppText.body(15, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('Start fresh. Your history stays.', style: AppText.body(12, color: AppColors.textDim)),
                  ],
                ),
              ),
              PillButton(label: 'Reset', onPressed: _resetting ? null : _reset),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text('Coins have no cash value and cannot be bought, sold or cashed out.', textAlign: TextAlign.center, style: AppText.body(11, color: AppColors.textFaint)),
      ],
    );
  }
}
