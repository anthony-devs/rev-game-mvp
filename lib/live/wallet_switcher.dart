import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../games/game_support.dart';
import '../pages/wallet_page.dart';
import '../user/bloc/profile_cubit.dart';
import 'deposit_sheet.dart';
import 'play_mode_switch.dart';
import 'withdraw_sheet.dart';

/// Tap the balance in the header: pick the wallet you play from, like the big betting apps do.
Future<void> showWalletSwitcher(BuildContext context) =>
    showAppBottomSheet<void>(context, title: 'Wallets', child: const _Switcher());

/// Small text action on the wallet page.
class SwitchWalletLink extends StatelessWidget {
  const SwitchWalletLink({super.key});

  @override
  Widget build(BuildContext context) {
    final live = context.select((ProfileCubit c) => c.state.live);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () async {
          await requestPlayMode(context, !live);
        },
        icon: Icon(Icons.swap_horiz_rounded, size: 18, color: AppColors.gold),
        label: Text(live ? 'Switch to coins' : 'Switch to live money', style: AppText.body(13, weight: FontWeight.w700, color: AppColors.gold)),
      ),
    );
  }
}

class _Switcher extends StatelessWidget {
  const _Switcher();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ProfileCubit>().state;
    // The sheet's own context dies when it closes; the root one outlives it.
    final root = Navigator.of(context, rootNavigator: true).context;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _WalletCard(
        title: 'Live money',
        subtitle: 'Real money. Wins and losses are real.',
        balance: s.liveWallet.balance,
        live: true,
        active: s.live,
        onSelect: () async {
          if (await requestPlayMode(context, true) && context.mounted) Navigator.of(context).pop();
        },
        actions: [
          Expanded(child: AppButton(label: 'Add money', variant: AppButtonVariant.gold, height: 44, fontSize: 14, onPressed: () {
            Navigator.of(context).pop();
            showDepositSheet(root);
          })),
          const SizedBox(width: 8),
          Expanded(child: AppButton(label: 'Withdraw', variant: AppButtonVariant.outline, height: 44, fontSize: 14, onPressed: () {
            Navigator.of(context).pop();
            showWithdrawSheet(root);
          })),
        ],
      ),
      const SizedBox(height: 10),
      _WalletCard(
        title: 'Coins',
        subtitle: 'Free to play. Not real money.',
        balance: s.demoWallet.balance,
        live: false,
        active: !s.live,
        onSelect: () async {
          if (await requestPlayMode(context, false) && context.mounted) Navigator.of(context).pop();
        },
      ),
      const SizedBox(height: 10),
      TextButton(
        onPressed: () {
          Navigator.of(context).pop();
          pushPage<void>(root, const WalletPage());
        },
        child: Text('Wallet details & history', style: AppText.body(13, weight: FontWeight.w700, color: AppColors.textMuted)),
      ),
    ]);
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.title, required this.subtitle, required this.balance, required this.live, required this.active, required this.onSelect, this.actions});

  final String title, subtitle;
  final double balance;
  final bool live, active;
  final VoidCallback onSelect;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final accent = live ? AppColors.loss : AppColors.mint;
    return PressScale(
      onTap: onSelect,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? accent : AppColors.lineStrong, width: active ? 1.6 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: AppText.body(15, weight: FontWeight.w800))),
            if (active) Text('PLAYING', style: AppText.body(10, weight: FontWeight.w800, color: accent, letterSpacing: 1)),
          ]),
          const SizedBox(height: 2),
          Text(subtitle, style: AppText.body(12, color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Text(live ? PlayMode.money(balance) : formatCredits(balance), style: AppText.number(24, color: accent)),
          if (actions != null) ...[const SizedBox(height: 12), Row(children: actions!)],
        ]),
      ),
    );
  }
}
