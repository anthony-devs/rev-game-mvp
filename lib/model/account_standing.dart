import 'package:equatable/equatable.dart';

import 'model_json.dart';

/// What staff can do to an account. Stored as `ban`, `suspension`,
/// `payout_restriction` and `investigation`.
enum StandingType {
  ban('ban', 4),
  suspension('suspension', 3),
  investigation('investigation', 2),
  payoutRestriction('payout_restriction', 1);

  const StandingType(this.wire, this.severity);
  final String wire;
  final int severity;

  static StandingType fromWire(Object? v) => StandingType.values.firstWhere((t) => t.wire == v, orElse: () => StandingType.payoutRestriction);
}

enum AppealStatus { none, pending, rejected }

/// One active ban, suspension, restriction or investigation.
class StandingAction extends Equatable {
  const StandingAction({
    required this.id,
    required this.type,
    this.reason = '',
    this.publicNote = '',
    this.expiresAt,
    this.blocksPlay = true,
    this.appealAllowed = true,
    this.appealStatus = AppealStatus.none,
    this.appealResponse,
    this.appealRetryAt,
  });

  final String id;
  final StandingType type;
  final String reason;

  /// Written by staff for the player: what happened and what to do next.
  final String publicNote;
  final DateTime? expiresAt;
  final bool blocksPlay;
  final bool appealAllowed;
  final AppealStatus appealStatus;
  final String? appealResponse;
  final DateTime? appealRetryAt;

  bool isActiveAt(DateTime now) => expiresAt == null || expiresAt!.isAfter(now);

  factory StandingAction.fromJson(Json j) => StandingAction(
        id: parseString(j['id']) ?? '',
        type: StandingType.fromWire(j['type']),
        reason: parseString(j['reason']) ?? '',
        publicNote: parseString(j['publicNote']) ?? '',
        expiresAt: parseDate(j['expiresAt']),
        blocksPlay: parseBool(j['blocksPlay'], true),
        appealAllowed: parseBool(j['appealAllowed'], true),
        appealStatus: enumByName(AppealStatus.values, j['appealStatus'], AppealStatus.none),
        appealResponse: parseString(j['appealResponse']),
        appealRetryAt: parseDate(j['appealRetryAt']),
      );

  @override
  List<Object?> get props => [id, type, reason, publicNote, expiresAt, blocksPlay, appealAllowed, appealStatus, appealResponse, appealRetryAt];
}

/// The player's account standing. Firestore: `users/{uid}/account/standing`
/// (written by the game server only). Everything is evaluated against a clock so
/// a suspension ends on time even if no new data arrives.
class AccountStanding extends Equatable {
  const AccountStanding({this.actions = const [], this.probationUntil, this.probationMaxBet = 1000});

  static const AccountStanding good = AccountStanding();

  final List<StandingAction> actions;
  final DateTime? probationUntil;
  final double probationMaxBet;

  List<StandingAction> activeAt(DateTime now) => [for (final a in actions) if (a.isActiveAt(now)) a];

  /// The most serious active action, or `null` when in good standing.
  StandingAction? topAt(DateTime now) {
    final act = activeAt(now);
    if (act.isEmpty) return null;
    return act.reduce((a, b) => b.type.severity > a.type.severity ? b : a);
  }

  /// The most serious action that stops play, or `null`.
  StandingAction? blockingAt(DateTime now) {
    final act = [for (final a in activeAt(now)) if (a.blocksPlay) a];
    if (act.isEmpty) return null;
    return act.reduce((a, b) => b.type.severity > a.type.severity ? b : a);
  }

  bool onProbationAt(DateTime now) => probationUntil != null && probationUntil!.isAfter(now);
  bool blocksPlayAt(DateTime now) => blockingAt(now) != null;
  bool blocksCreditsAt(DateTime now) => activeAt(now).isNotEmpty || onProbationAt(now);

  /// The next moment anything here changes by itself (a suspension ending,
  /// probation ending, an appeal cooldown ending). `null` if nothing will.
  DateTime? nextChangeAfter(DateTime now) {
    DateTime? best;
    void consider(DateTime? t) {
      if (t != null && t.isAfter(now) && (best == null || t.isBefore(best!))) best = t;
    }

    for (final a in actions) {
      consider(a.expiresAt);
      consider(a.appealRetryAt);
    }
    consider(probationUntil);
    return best;
  }

  factory AccountStanding.fromFirestore(Json data) {
    final raw = data['active'];
    return AccountStanding(
      actions: raw is List ? [for (final e in raw) StandingAction.fromJson(parseMap(e))] : const [],
      probationUntil: parseDate(data['probationUntil']),
    );
  }

  @override
  List<Object?> get props => [actions, probationUntil, probationMaxBet];
}
