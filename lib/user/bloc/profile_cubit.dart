import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../components/core/app_haptics.dart';
import '../../components/core/app_sound.dart';
import '../../core/api/api_client.dart';
import '../../model/model.dart';
import '../data/user_repository.dart';
import '../data/wallet_api.dart';

class ProfileState extends Equatable {
  const ProfileState({
    this.user = AppUser.empty,
    this.wallet = Wallet.empty,
    this.settings = UserSettings.defaults,
    this.limits = PlayLimits.defaults,
    this.progress = PlayerProgress.initial,
    this.walletReady = false,
    this.profileReady = false,
    this.heldBalance,
    this.standing = AccountStanding.good,
    this.standingAt,
  });

  final AppUser user;
  final Wallet wallet;
  final UserSettings settings;
  final PlayLimits limits;
  final PlayerProgress progress;

  /// `false` until the wallet has loaded, so screens can show a placeholder
  /// instead of a wrong 0 balance.
  final bool walletReady;

  /// `false` until the profile document has loaded (needed before the age gate).
  final bool profileReady;

  /// While a round is animating the screen keeps showing this number, so the
  /// balance never jumps before the player sees the result. `null` = live.
  final double? heldBalance;

  /// THE balance every screen shows. One source: the Firestore wallet, optionally
  /// held for the length of a round animation.
  double get balance => heldBalance ?? wallet.balance;

  /// Bans, suspensions, restrictions, investigations. Live from Firestore.
  final AccountStanding standing;

  /// Clock for [standing]; moves forward when a suspension or probation ends.
  final DateTime? standingAt;

  DateTime get _now => standingAt ?? DateTime.now();

  /// The action that currently stops this player from playing, or `null`.
  StandingAction? get blockingAction => standing.blockingAt(_now);
  bool get blocksPlay => blockingAction != null;

  /// Free credits (daily, top-up, reset) are paused: an active action or probation.
  bool get blocksCredits => standing.blocksCreditsAt(_now);
  bool get onProbation => standing.onProbationAt(_now);

  /// Largest bet while on probation, otherwise `null`.
  double? get probationMaxBet => onProbation ? standing.probationMaxBet : null;

  /// Active actions that don't stop play (for a banner).
  List<StandingAction> get softActions => [for (final a in standing.activeAt(_now)) if (!a.blocksPlay) a];

  ProfileState copyWith({
    AppUser? user,
    Wallet? wallet,
    UserSettings? settings,
    PlayLimits? limits,
    PlayerProgress? progress,
    bool? walletReady,
    bool? profileReady,
    Object? heldBalance = _keep,
    AccountStanding? standing,
    DateTime? standingAt,
  }) {
    return ProfileState(
      user: user ?? this.user,
      wallet: wallet ?? this.wallet,
      settings: settings ?? this.settings,
      limits: limits ?? this.limits,
      progress: progress ?? this.progress,
      walletReady: walletReady ?? this.walletReady,
      profileReady: profileReady ?? this.profileReady,
      heldBalance: identical(heldBalance, _keep) ? this.heldBalance : heldBalance as double?,
      standing: standing ?? this.standing,
      standingAt: standingAt ?? this.standingAt,
    );
  }

  @override
  List<Object?> get props => [user, wallet, settings, limits, progress, walletReady, profileReady, heldBalance, standing, standingAt];
}

const Object _keep = Object();

/// The signed-in player's live data: profile, wallet, settings, limits and
/// progress. Lives for the whole app and re-binds when the player changes.
///
/// ```dart
/// final balance = context.select((ProfileCubit c) => c.state.wallet.balance);
/// context.read<ProfileCubit>().updateSettings(settings.copyWith(soundEnabled: false));
/// ```
class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit(this._repo, this._walletApi) : super(const ProfileState());

  final UserRepository _repo;
  final WalletApi _walletApi;
  final List<StreamSubscription<Object?>> _subs = [];
  Timer? _holdGuard;
  Timer? _standingTimer;

  /// Call with the auth user whenever sign in changes. Pass [AppUser.empty]
  /// when signed out.
  void bind(AppUser auth) {
    _cancel();
    if (auth.isEmpty) {
      AppHaptics.enabled = true;
      AppSound.stopMusic();
      unfreeze();
      emit(const ProfileState());
      return;
    }

    // Show something instantly (name from sign in); Firestore fills in after.
    emit(ProfileState(user: auth, wallet: Wallet(userId: auth.id)));

    _subs
      ..add(_repo.watchProfile(auth.id).listen((p) {
        if (p == null) return;
        AppHaptics.enabled = p.settings.hapticsEnabled;
        AppSound.apply(sound: p.settings.soundEnabled, music: p.settings.musicEnabled);
        emit(state.copyWith(user: p.user, settings: p.settings, limits: p.limits, profileReady: true));
      }, onError: (_) {}))
      ..add(_repo.watchWallet(auth.id).listen((w) {
        if (w == null) return;
        emit(state.copyWith(wallet: w, walletReady: true));
      }, onError: (_) {}))
      ..add(_repo.watchProgress(auth.id).listen((p) {
        if (p == null) return;
        emit(state.copyWith(progress: p));
      }, onError: (_) {}))
      ..add(_repo.watchStanding(auth.id).listen((st) {
        emit(state.copyWith(standing: st, standingAt: DateTime.now()));
        _scheduleStandingTick();
      }, onError: (_) {}));

    unawaited(_repo.ensureDocs(auth));
  }

  // ---- Account standing ---------------------------------------------------

  /// Wakes up when a suspension, probation or appeal cooldown ends, so the app
  /// reacts on time. The server is asked to settle it too (it is the authority).
  void _scheduleStandingTick() {
    _standingTimer?.cancel();
    final next = state.standing.nextChangeAfter(DateTime.now());
    if (next == null) return;
    final wait = next.difference(DateTime.now()) + const Duration(seconds: 1);
    _standingTimer = Timer(wait.isNegative ? const Duration(seconds: 1) : wait, () {
      emit(state.copyWith(standingAt: DateTime.now()));
      unawaited(_walletApi.refreshStanding().catchError((Object _) {}));
      _scheduleStandingTick();
    });
  }

  /// Ask the server to re-check (used after it refused something).
  Future<void> refreshStanding() => _walletApi.refreshStanding();

  /// Appeal an active action. Throws [ApiException].
  Future<void> appeal(String actionId, String message, {List<String> attachments = const []}) =>
      _walletApi.appeal(actionId, message, attachments: attachments);

  /// Thrown instead of calling the server when free credits are paused.
  ApiException get _creditsPaused => ApiException(
        403,
        'credits_restricted',
        state.blockingAction != null || state.standing.activeAt(DateTime.now()).isNotEmpty
            ? 'Free credits are paused while your account has an open restriction.'
            : 'Free credits are paused while your account is on probation.',
      );

  // ---- Player edits (UI updates at once through the live listener) --------

  Future<void> updateSettings(UserSettings settings) {
    AppHaptics.enabled = settings.hapticsEnabled;
    AppSound.apply(sound: settings.soundEnabled, music: settings.musicEnabled);
    emit(state.copyWith(settings: settings)); // instant, no wait for the network
    return _repo.saveSettings(state.user.id, settings);
  }

  Future<void> updateLimits(PlayLimits limits) {
    emit(state.copyWith(limits: limits));
    return _repo.saveLimits(state.user.id, limits);
  }

  Future<void> rename(String name) => _repo.rename(state.user.id, name);

  Future<void> confirmAge() async {
    emit(state.copyWith(user: state.user.copyWith(ageConfirmed: true))); // instant
    try {
      await _repo.confirmAge(state.user.id);
    } catch (_) {
      emit(state.copyWith(user: state.user.copyWith(ageConfirmed: false)));
      rethrow;
    }
  }

  // ---- One balance, held during animations --------------------------------

  /// Keep showing [shown] (usually balance minus the bet) until [unfreeze].
  /// A safety timer releases it after 3 minutes so a crash can never leave the
  /// header stuck.
  void freeze(double shown) {
    _holdGuard?.cancel();
    _holdGuard = Timer(const Duration(minutes: 3), unfreeze);
    emit(state.copyWith(heldBalance: shown));
  }

  /// Show the live Firestore balance again.
  void unfreeze() {
    _holdGuard?.cancel();
    _holdGuard = null;
    if (state.heldBalance != null) emit(state.copyWith(heldBalance: null));
  }

  // ---- Wallet actions (the new balance arrives through the live listener) --

  /// Claims the daily credits. Returns the claim, or throws [ApiException].
  Future<DailyClaim> claimDaily() => state.blocksCredits ? Future.error(_creditsPaused) : _walletApi.claimDaily();

  /// Refill to the starting balance when low.
  Future<void> topUp() => state.blocksCredits ? Future.error(_creditsPaused) : _walletApi.topUp();

  /// Back to the starting balance. History and level stay.
  Future<void> resetBalance() => state.blocksCredits ? Future.error(_creditsPaused) : _walletApi.reset();

  /// Deletes the account on the server. The caller signs out afterwards.
  Future<void> deleteAccount() => _walletApi.deleteAccount();

  /// Friendly text for any failure.
  static String errorText(Object e) => e is ApiException ? e.message : 'Something went wrong. Please try again.';

  void _cancel() {
    _standingTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  @override
  Future<void> close() {
    _holdGuard?.cancel();
    _standingTimer?.cancel();
    _cancel();
    return super.close();
  }
}
