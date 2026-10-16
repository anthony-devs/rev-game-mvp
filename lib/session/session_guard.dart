import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../model/model.dart';
import '../user/bloc/profile_cubit.dart';

enum SessionAlert { none, realityCheck, lossLimit }

class SessionState extends Equatable {
  const SessionState({
    this.startedAt,
    this.totalBet = 0,
    this.net = 0,
    this.alert = SessionAlert.none,
    this.alertSerial = 0,
  });

  final DateTime? startedAt;

  /// Credits bet this session.
  final double totalBet;

  /// Won minus bet this session (negative = down).
  final double net;
  final SessionAlert alert;

  /// Bumps every time an alert is raised, so the same alert can fire again.
  final int alertSerial;

  Duration playedFor(DateTime now) => startedAt == null ? Duration.zero : now.difference(startedAt!);

  SessionState copyWith({DateTime? startedAt, double? totalBet, double? net, SessionAlert? alert, int? alertSerial}) {
    return SessionState(
      startedAt: startedAt ?? this.startedAt,
      totalBet: totalBet ?? this.totalBet,
      net: net ?? this.net,
      alert: alert ?? this.alert,
      alertSerial: alertSerial ?? this.alertSerial,
    );
  }

  @override
  List<Object?> get props => [startedAt, totalBet, net, alert, alertSerial];
}

/// Responsible-play tools: reality check, session loss limit, cool-off and the
/// player's own max bet. The limits are the player's own choice, stored in
/// Firestore, and enforced here in the app (the server does not check them).
///
/// A game page calls [enter] when it opens and [leave] when it closes, asks
/// [blockReason] before every round, and reports each result with [record].
class SessionGuard extends Cubit<SessionState> {
  SessionGuard(this._profile) : super(const SessionState());

  final ProfileCubit _profile;
  Timer? _timer;
  int _inGame = 0;
  DateTime? _lastCheckAt;

  PlayLimits get _limits => _profile.state.limits;

  /// A game screen opened.
  void enter() {
    _inGame++;
    final now = DateTime.now();
    if (state.startedAt == null) emit(state.copyWith(startedAt: now));
    _lastCheckAt ??= now;
    _timer ??= Timer.periodic(const Duration(seconds: 20), (_) => _tick());
  }

  /// A game screen closed.
  void leave() {
    if (_inGame > 0) _inGame--;
    if (_inGame == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Start a new session (sign in or out).
  void reset() {
    _timer?.cancel();
    _timer = null;
    _inGame = 0;
    _lastCheckAt = null;
    emit(const SessionState());
  }

  /// Why the player cannot start a round right now, or `null` when they can.
  String? blockReason() {
    final now = DateTime.now();
    final l = _limits;
    if (l.isCoolingOff(now)) {
      final left = l.coolOffUntil!.difference(now);
      final txt = left.inHours >= 1 ? '${left.inHours}h ${left.inMinutes % 60}m' : '${left.inMinutes + 1} min';
      return 'You are taking a break. Play opens again in $txt.';
    }
    final loss = l.sessionLossLimit;
    if (loss != null && loss > 0 && -state.net >= loss) {
      return 'You reached your session loss limit. Take a break or change it in Play limits.';
    }
    if (l.hasSessionLimit && state.playedFor(now).inMinutes >= l.sessionLimitMinutes) {
      return 'Your session time limit is up. Start a new session from Play limits.';
    }
    return null;
  }

  /// The biggest bet the player allows themselves (their own cap), or [gameMax].
  double maxBet(double gameMax) {
    final cap = _limits.maxBetCap;
    return cap == null || cap <= 0 ? gameMax : (cap < gameMax ? cap : gameMax);
  }

  /// Report a settled round. `payout` is what came back (0 for a loss).
  void record({required double bet, required double payout}) {
    final s = state;
    final next = s.copyWith(totalBet: s.totalBet + bet, net: s.net + payout - bet);
    emit(next);
    final loss = _limits.sessionLossLimit;
    if (loss != null && loss > 0 && -next.net >= loss) _raise(SessionAlert.lossLimit);
  }

  /// "Continue playing" on the reality check: start counting again.
  void acknowledge() {
    _lastCheckAt = DateTime.now();
    emit(state.copyWith(alert: SessionAlert.none));
  }

  /// Fresh session numbers after a break.
  void startNewSession() {
    _lastCheckAt = DateTime.now();
    emit(SessionState(startedAt: DateTime.now(), alertSerial: state.alertSerial));
  }

  void _tick() {
    final l = _limits;
    if (_inGame == 0 || !l.hasRealityCheck) return;
    final last = _lastCheckAt ?? DateTime.now();
    if (DateTime.now().difference(last).inMinutes >= l.realityCheckMinutes && state.alert == SessionAlert.none) {
      _raise(SessionAlert.realityCheck);
    }
  }

  void _raise(SessionAlert a) => emit(state.copyWith(alert: a, alertSerial: state.alertSerial + 1));

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
