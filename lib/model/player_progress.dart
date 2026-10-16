import 'package:equatable/equatable.dart';

import 'model_json.dart';

/// Level, XP and streak. Firestore path: `users/{uid}/progress/current`.
class PlayerProgress extends Equatable {
  const PlayerProgress({
    this.level = 1,
    this.xp = 0,
    this.xpForNext = 1000,
    this.streakDays = 0,
    this.totalRounds = 0,
    this.biggestWin = 0,
    this.lastPlayedAt,
  });

  static const PlayerProgress initial = PlayerProgress();

  final int level;
  final int xp;
  final int xpForNext;
  final int streakDays;
  final int totalRounds;
  final double biggestWin;
  final DateTime? lastPlayedAt;

  /// 0.0 to 1.0, for `AppProgressBar(value: progress.fraction)`.
  double get fraction => xpForNext <= 0 ? 0 : (xp / xpForNext).clamp(0.0, 1.0);

  PlayerProgress copyWith({
    int? level,
    int? xp,
    int? xpForNext,
    int? streakDays,
    int? totalRounds,
    double? biggestWin,
    DateTime? lastPlayedAt,
  }) {
    return PlayerProgress(
      level: level ?? this.level,
      xp: xp ?? this.xp,
      xpForNext: xpForNext ?? this.xpForNext,
      streakDays: streakDays ?? this.streakDays,
      totalRounds: totalRounds ?? this.totalRounds,
      biggestWin: biggestWin ?? this.biggestWin,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    );
  }

  factory PlayerProgress.fromJson(Json json) => PlayerProgress(
        level: parseInt(json['level'], 1),
        xp: parseInt(json['xp']),
        xpForNext: parseInt(json['xpForNext'], 1000),
        streakDays: parseInt(json['streakDays']),
        totalRounds: parseInt(json['totalRounds']),
        biggestWin: parseDouble(json['biggestWin']),
        lastPlayedAt: parseDate(json['lastPlayedAt']),
      );

  Json toJson() => {
        'level': level,
        'xp': xp,
        'xpForNext': xpForNext,
        'streakDays': streakDays,
        'totalRounds': totalRounds,
        'biggestWin': biggestWin,
        'lastPlayedAt': dateToMs(lastPlayedAt),
      };

  factory PlayerProgress.fromFirestore(Json data) => PlayerProgress.fromJson(data);

  Json toFirestore() => {...toJson(), 'lastPlayedAt': lastPlayedAt};

  @override
  List<Object?> get props => [level, xp, xpForNext, streakDays, totalRounds, biggestWin, lastPlayedAt];
}
