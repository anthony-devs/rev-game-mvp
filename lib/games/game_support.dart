import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../core/api/api_client.dart';
import '../pages/fairness_page.dart';
import '../pages/get_credits_sheet.dart';
import '../session/session_guard.dart';
import '../user/bloc/profile_cubit.dart';

/// Push a page on the app navigator.
Future<T?> pushPage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: (_) => page));

/// The one balance every screen shows: the Firestore wallet, held steady while
/// a round is animating. Rebuilds the widget when it changes.
double watchBalance(BuildContext context) => context.select((ProfileCubit c) => c.state.balance);

/// Opens the Fairness screen. Pass a round id to verify that round.
void openFairness(BuildContext context, {String? roundId}) => pushPage<void>(context, FairnessPage(roundId: roundId));

/// Sheet shown when the player cannot afford a bet.
Future<void> showNoCredits(BuildContext context, {double? needed}) {
  return showAppBottomSheet<void>(
    context,
    title: 'Not enough credits',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          needed == null
              ? 'Your balance is too low for this bet. Lower the bet or get free demo credits.'
              : 'You need ${formatCredits(needed, decimals: 0)} credits for this bet. Lower it or get free demo credits.',
          style: AppText.body(14, color: AppColors.textMuted, height: 1.5),
        ),
        const SizedBox(height: 20),
        AppButton(
          label: 'Get demo credits',
          variant: AppButtonVariant.gold,
          onPressed: () {
            Navigator.of(context).pop();
            showGetCredits(context);
          },
        ),
        const SizedBox(height: 10),
        AppButton(label: 'Lower my bet', variant: AppButtonVariant.outline, height: 52, onPressed: () => Navigator.of(context).pop()),
      ],
    ),
  );
}

/// A short message at the bottom of the screen.
void showToast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: error ? AppColors.loss : AppColors.lineStrong)),
      content: Text(message, style: AppText.body(14, color: error ? AppColors.loss : AppColors.text)),
    ));
}

/// What went wrong with a server call, in plain words.
enum FailKind { network, noCredits, other }

FailKind failKind(Object e) {
  if (e is ApiException) {
    if (e.isNetwork) return FailKind.network;
    if (e.code == 'insufficient_credits') return FailKind.noCredits;
  }
  return FailKind.other;
}

String failText(Object e) => e is ApiException ? e.message : 'Something went wrong. Please try again.';

/// Shared behaviour of every game screen. Mix into the page's `State`:
///
///  * tells the [SessionGuard] the player is in a game (reality checks),
///  * holds the displayed balance while a round animates,
///  * always releases the held balance when the page closes.
mixin GameSessionMixin<T extends StatefulWidget> on State<T> {
  late final SessionGuard _guard = context.read<SessionGuard>();
  late final ProfileCubit _profile = context.read<ProfileCubit>();

  SessionGuard get guard => _guard;
  ProfileCubit get profile => _profile;

  /// The real wallet balance (ignores any hold).
  double get walletBalance => _profile.state.wallet.balance;

  @override
  void initState() {
    super.initState();
    _guard.enter();
    AppSound.startMusic();
  }

  @override
  void dispose() {
    _guard.leave();
    _profile.unfreeze();
    super.dispose();
  }

  /// `false` (and a message) if a limit stops the player from betting now.
  bool checkCanPlay() {
    final reason = _guard.blockReason();
    if (reason != null) {
      AppSound.play(Sfx.error);
      showToast(context, reason, error: true);
      return false;
    }
    return true;
  }

  /// Largest bet allowed: the game's max, the player's own cap, and what they have.
  double maxBetFor(double gameMax) {
    return _guard.maxBet(gameMax);
  }

  /// Show [shown] until [releaseBalance]. Use at the start of a round.
  void holdBalance(double shown) => _profile.freeze(shown);

  void releaseBalance() => _profile.unfreeze();

  /// Round finished: report to the session guard.
  void reportRound({required double bet, required double payout}) => _guard.record(bet: bet, payout: payout);
}
