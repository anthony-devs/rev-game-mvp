import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../components/core/app_haptics.dart';
import '../../components/core/app_sound.dart';
import '../../components/core/play_mode.dart';
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
    this.live = false,
    this.demoWallet = Wallet.empty,
    this.liveWallet = Wallet.empty,
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

  /// Playing with real money. Wallet, progress and history then come from the live record.
  final bool live;

  /// Both wallets are always kept up to date, so the wallet picker can show both balances.
  final Wallet demoWallet, liveWallet;

  /// Which player record the app reads (wallet, rounds, level, fairness seeds).
  String get dataId => live && !user.isEmpty ? 'L_${user.id}' : user.id;

  DateTime get _now => standingAt ?? DateTime.now();

  /// The action that currently stops this player from playing, or `null`.
  StandingAction? get blockingAction => standing.blockingAt(_now);
  bool get blocksPlay => blockingAction != null;

  /// Free coins (daily, top-up, reset) are paused: an active action or probation.
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
    bool? live,
    Wallet? demoWallet,
    Wallet? liveWallet,
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
      live: live ?? this.live,
      demoWallet: demoWallet ?? this.demoWallet,
      liveWallet: liveWallet ?? this.liveWallet,
    );
  }

  @override
  List<Object?> get props => [user, wallet, settings, limits, progress, walletReady, profileReady, heldBalance, standing, standingAt, live, demoWallet, liveWallet];
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
  final List<StreamSubscription<Object?>> _dataSubs = []; // wallet + progress: demo or live record
  Timer? _holdGuard;
  Timer? _standingTimer;

  /// Call with the auth user whenever sign in changes. Pass [AppUser.empty]
  /// when signed out.
  void bind(AppUser auth) {
    _cancel();
    PlayMode.live.value = false; // always start a session on demo coins
    if (auth.isEmpty) {
      AppHaptics.enabled = true;
      AppSound.reset();
      unfreeze();
      emit(const ProfileState());
      return;
    }

    // A new player starts from the defaults, never the last player's switches.
    AppHaptics.enabled = true;
    AppSound.apply(sound: true, music: true);

    // Show something instantly (name from sign in); Firestore fills in after.
    emit(ProfileState(user: auth, wallet: Wallet(userId: auth.id)));

    _subs
      ..add(_repo.watchProfile(auth.id).listen((p) {
        if (p == null) return;
        AppHaptics.enabled = p.settings.hapticsEnabled;
        AppSound.apply(sound: p.settings.soundEnabled, music: p.settings.musicEnabled);
        emit(state.copyWith(user: p.user, settings: p.settings, limits: p.limits, profileReady: true));
      }, onError: (_) {}))
      ..add(_repo.watchStanding(auth.id).listen((st) {
        emit(state.copyWith(standing: st, standingAt: DateTime.now()));
        _scheduleStandingTick();
      }, onError: (_) {}));

    _bindData();
    unawaited(_repo.ensureDocs(auth));
  }

  /// Wallet and progress for the current mode. Demo reads `users/<uid>`, live reads `users/L_<uid>`
  /// (the server owns it; the rules let only that player read it).
  void _bindData() {
    for (final s in _dataSubs) {
      s.cancel();
    }
    _dataSubs.clear();
    final uid = state.user.id;
    if (uid.isEmpty) return;
    // Both wallets are watched all the time (cheap, one document each): the active one
    // drives every screen, the other one only feeds the wallet picker.
    _dataSubs
      ..add(_repo.watchWallet(uid).listen((w) {
        if (w == null) return;
        emit(state.copyWith(demoWallet: w, wallet: state.live ? null : w, walletReady: state.live ? null : true));
      }, onError: (_) {}))
      // No live document yet just means R0 (nothing deposited): not "still loading".
      ..add(_repo.watchWallet('L_$uid').listen((w) {
        final lw = w ?? Wallet(userId: uid);
        emit(state.copyWith(liveWallet: lw, wallet: state.live ? lw : null, walletReady: state.live ? true : null));
      }, onError: (_) {}))
      ..add(_repo.watchProgress(state.dataId).listen((p) {
        if (p == null) return;
        emit(state.copyWith(progress: p));
      }, onError: (_) {}));
  }

  /// Switch between demo coins and live money. Call it only from the lobby / wallet,
  /// never in the middle of a round.
  void setLive(bool live) {
    if (state.live == live || state.user.isEmpty) return;
    PlayMode.live.value = live;
    unfreeze();
    emit(state.copyWith(
      live: live,
      wallet: live ? state.liveWallet : state.demoWallet,
      walletReady: true,
      progress: PlayerProgress.initial,
    ));
    _bindData();
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

  /// Thrown instead of calling the server when free coins are paused.
  ApiException get _creditsPaused => ApiException(
        403,
        'credits_restricted',
        state.blockingAction != null || state.standing.activeAt(DateTime.now()).isNotEmpty
            ? 'Free coins are paused while your account has an open restriction.'
            : 'Free coins are paused while your account is on probation.',
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

  /// Claims the daily coins. Returns the claim, or throws [ApiException].
  Future<DailyClaim> claimDaily() => state.blocksCredits ? Future.error(_creditsPaused) : _walletApi.claimDaily();

  /// Refill to the starting balance when low.
  Future<void> topUp() => state.blocksCredits ? Future.error(_creditsPaused) : _walletApi.topUp();

  /// Back to the starting balance. History and level stay.
  Future<void> resetBalance() => state.blocksCredits ? Future.error(_creditsPaused) : _walletApi.reset();

  /// Deletes the account on the server. The caller signs out afterwards.
  Future<void> deleteAccount() => _walletApi.deleteAccount();

  /// Friendly text for any failure.
  static String errorText(Object e) => e is ApiException ? e.message : "That didn't work. Please check your connection and try again.";

  void _cancel() {
    _standingTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    for (final s in _dataSubs) {
      s.cancel();
    }
    _dataSubs.clear();
  }

  @override
  Future<void> close() {
    _holdGuard?.cancel();
    _standingTimer?.cancel();
    _cancel();
    return super.close();
  }
}
