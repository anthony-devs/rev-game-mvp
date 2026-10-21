import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../games/game_support.dart';
import '../user/bloc/profile_cubit.dart';
import 'agreement_page.dart';
import 'live_cubit.dart';

bool _understood = false;

/// Moves the whole app to live money or demo coins. Going live asks the player to confirm
/// once and checks with the server that live play is open for them. Returns true if it switched.
bool _switching = false;

Future<bool> requestPlayMode(BuildContext context, bool live) async {
  if (_switching) return false; // a second tap while the first is still working
  _switching = true;
  try {
    return await _requestPlayMode(context, live);
  } finally {
    _switching = false;
  }
}

Future<bool> _requestPlayMode(BuildContext context, bool live) async {
  final profile = context.read<ProfileCubit>();
  final cubit = context.read<LiveCubit>();
  if (profile.state.live == live) return true;
  if (!live) {
    profile.setLive(false);
    return true;
  }
  // Load the live status first: it says whether live play is open and whether this player still has to
  // accept the Live Money Agreement.
  final err = await cubit.enter();
  if (!context.mounted) return false;
  if (err != null) {
    showToast(context, err, error: true);
    return false;
  }
  final status = cubit.state.status;
  if (status != null && status.needsAgreement) {
    if (!await showLiveAgreement(context) || !context.mounted) return false;
    await cubit.refresh();
  } else if (!_understood && !(status?.agreementRequired ?? false)) {
    final ok = await showAppBottomSheet<bool>(context, title: 'Play with real money?', child: const _Intro());
    if (ok != true || !context.mounted) return false;
    _understood = true;
  }
  profile.setLive(true);
  return true;
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Live mode uses your own money, not your free coins. Wins and losses are real, and your coins balance is not affected.',
          style: AppText.body(14, color: AppColors.textMuted, height: 1.5),
        ),
        const SizedBox(height: 12),
        for (final t in const ['You must be 18 or older.', 'Only play with money you can afford to lose.', 'Every payout is checked by our team before it is sent.', 'Playing uses rounds: you get free rounds that refresh over time, and can buy extra rounds.', 'You can set limits any time in Settings.'])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.check_rounded, size: 18, color: AppColors.green),
              const SizedBox(width: 8),
              Expanded(child: Text(t, style: AppText.body(14, color: AppColors.textSoft))),
            ]),
          ),
        const SizedBox(height: 18),
        AppButton(label: 'I understand, go live', variant: AppButtonVariant.gold, onPressed: () => Navigator.of(context).pop(true)),
        const SizedBox(height: 10),
        AppButton(label: 'Stay on coins', variant: AppButtonVariant.outline, height: 52, onPressed: () => Navigator.of(context).pop(false)),
      ],
    );
  }
}
