import 'package:equatable/equatable.dart';

import 'model_json.dart';

/// Responsible play controls. Firestore path: `users/{uid}/settings/limits`.
/// A value of 0 (or null) means the control is off.
class PlayLimits extends Equatable {
  const PlayLimits({
    this.realityCheckMinutes = 60,
    this.sessionLimitMinutes = 0,
    this.maxBetCap,
    this.sessionLossLimit,
    this.coolOffUntil,
  });

  static const PlayLimits defaults = PlayLimits();

  /// Show the "time check" dialog every N minutes.
  final int realityCheckMinutes;

  /// Stop play after N minutes in one session.
  final int sessionLimitMinutes;

  /// Highest bet the player allows themselves.
  final double? maxBetCap;

  /// Stop play when the player has lost this many coins in one session.
  final double? sessionLossLimit;

  /// Play is blocked until this time.
  final DateTime? coolOffUntil;

  bool get hasRealityCheck => realityCheckMinutes > 0;
  bool get hasSessionLimit => sessionLimitMinutes > 0;
  bool isCoolingOff(DateTime now) => coolOffUntil != null && now.isBefore(coolOffUntil!);

  /// Clamp a bet to the player's own cap.
  double capBet(double bet) => maxBetCap == null ? bet : (bet > maxBetCap! ? maxBetCap! : bet);

  PlayLimits copyWith({
    int? realityCheckMinutes,
    int? sessionLimitMinutes,
    double? maxBetCap,
    double? sessionLossLimit,
    DateTime? coolOffUntil,
  }) {
    return PlayLimits(
      realityCheckMinutes: realityCheckMinutes ?? this.realityCheckMinutes,
      sessionLimitMinutes: sessionLimitMinutes ?? this.sessionLimitMinutes,
      maxBetCap: maxBetCap ?? this.maxBetCap,
      sessionLossLimit: sessionLossLimit ?? this.sessionLossLimit,
      coolOffUntil: coolOffUntil ?? this.coolOffUntil,
    );
  }

  factory PlayLimits.fromJson(Json json) => PlayLimits(
        realityCheckMinutes: parseInt(json['realityCheckMinutes'], 60),
        sessionLimitMinutes: parseInt(json['sessionLimitMinutes']),
        maxBetCap: json['maxBetCap'] == null ? null : parseDouble(json['maxBetCap']),
        sessionLossLimit: json['sessionLossLimit'] == null ? null : parseDouble(json['sessionLossLimit']),
        coolOffUntil: parseDate(json['coolOffUntil']),
      );

  Json toJson() => {
        'realityCheckMinutes': realityCheckMinutes,
        'sessionLimitMinutes': sessionLimitMinutes,
        'maxBetCap': maxBetCap,
        'sessionLossLimit': sessionLossLimit,
        'coolOffUntil': dateToMs(coolOffUntil),
      };

  factory PlayLimits.fromFirestore(Json data) => PlayLimits.fromJson(data);

  Json toFirestore() => {
        'realityCheckMinutes': realityCheckMinutes,
        'sessionLimitMinutes': sessionLimitMinutes,
        'maxBetCap': maxBetCap,
        'sessionLossLimit': sessionLossLimit,
        'coolOffUntil': coolOffUntil,
      };

  @override
  List<Object?> get props => [realityCheckMinutes, sessionLimitMinutes, maxBetCap, sessionLossLimit, coolOffUntil];
}
