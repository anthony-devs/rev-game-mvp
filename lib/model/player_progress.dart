import 'package:equatable/equatable.dart';

import 'model_json.dart';

/// Level, XP and streak. Firestore path: `users/{uid}/progress/current`.
class PlayerProgress extends Equatable {
  const PlayerProgress({
    this.level = 1,
    this.xp = 0,
    this.xpForNext = 500,
    this.streakDays = 0,
    this.totalRounds = 0,
    this.totalWins = 0,
    this.biggestWin = 0,
    this.bestMultiplier = 0,
    this.lastPlayedAt,
  });

  static const PlayerProgress initial = PlayerProgress();

  final int level;
  final int xp;
  final int xpForNext;
  final int streakDays;
  final int totalRounds;
  final int totalWins;
  final double biggestWin;
  final double bestMultiplier;
  final DateTime? lastPlayedAt;

  /// 0.0 to 1.0, for `AppProgressBar(value: progress.fraction)`.
  /// Win rate 0.0 to 1.0.
  double get winRate => totalRounds == 0 ? 0 : totalWins / totalRounds;

  double get fraction => xpForNext <= 0 ? 0 : (xp / xpForNext).clamp(0.0, 1.0);

  PlayerProgress copyWith({
    int? level,
    int? xp,
    int? xpForNext,
    int? streakDays,
    int? totalRounds,
    int? totalWins,
    double? biggestWin,
    double? bestMultiplier,
    DateTime? lastPlayedAt,
  }) {
    return PlayerProgress(
      level: level ?? this.level,
      xp: xp ?? this.xp,
      xpForNext: xpForNext ?? this.xpForNext,
      streakDays: streakDays ?? this.streakDays,
      totalRounds: totalRounds ?? this.totalRounds,
      totalWins: totalWins ?? this.totalWins,
      biggestWin: biggestWin ?? this.biggestWin,
      bestMultiplier: bestMultiplier ?? this.bestMultiplier,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    );
  }

  factory PlayerProgress.fromJson(Json json) => PlayerProgress(
        level: parseInt(json['level'], 1),
        xp: parseInt(json['xp']),
        xpForNext: parseInt(json['xpForNext'], 500),
        streakDays: parseInt(json['streakDays']),
        totalRounds: parseInt(json['totalRounds']),
        totalWins: parseInt(json['totalWins']),
        biggestWin: parseDouble(json['biggestWin']),
        bestMultiplier: parseDouble(json['bestMultiplier']),
        lastPlayedAt: parseDate(json['lastPlayedAt']),
      );

  Json toJson() => {
        'level': level,
        'xp': xp,
        'xpForNext': xpForNext,
        'streakDays': streakDays,
        'totalRounds': totalRounds,
        'totalWins': totalWins,
        'biggestWin': biggestWin,
        'bestMultiplier': bestMultiplier,
        'lastPlayedAt': dateToMs(lastPlayedAt),
      };

  factory PlayerProgress.fromFirestore(Json data) => PlayerProgress.fromJson(data);

  Json toFirestore() => {...toJson(), 'lastPlayedAt': lastPlayedAt};

  @override
  List<Object?> get props => [level, xp, xpForNext, streakDays, totalRounds, totalWins, biggestWin, bestMultiplier, lastPlayedAt];
}
