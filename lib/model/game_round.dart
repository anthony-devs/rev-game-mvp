import 'package:equatable/equatable.dart';

import 'fairness_proof.dart';
import 'game_type.dart';
import 'model_json.dart';

enum RoundStatus { pending, won, lost, cashedOut, voided }

/// One played round. Firestore path: `users/{uid}/rounds/{id}`.
/// Powers History, the Wallet activity list and Verify a round.
class GameRound extends Equatable {
  const GameRound({
    required this.id,
    required this.userId,
    required this.game,
    required this.bet,
    required this.createdAt,
    this.payout = 0,
    this.multiplier = 0,
    this.status = RoundStatus.pending,
    this.settledAt,
    this.fairness,
    this.details = const {},
  });

  final String id;
  final String userId;
  final GameType game;
  final double bet;
  final double payout;

  /// Final multiplier (cash out point, slots line multiplier, crash point).
  final double multiplier;
  final RoundStatus status;
  final DateTime createdAt;
  final DateTime? settledAt;
  final FairnessProof? fairness;

  /// Game-specific result: reels, cards, dice roll, winning number.
  final Map<String, dynamic> details;

  /// Profit or loss, for `ActivityRow(amount: round.net)`.
  double get net => payout - bet;
  bool get isSettled => status != RoundStatus.pending;
  bool get isWin => status == RoundStatus.won || status == RoundStatus.cashedOut;

  GameRound copyWith({
    double? payout,
    double? multiplier,
    RoundStatus? status,
    DateTime? settledAt,
    FairnessProof? fairness,
    Map<String, dynamic>? details,
  }) {
    return GameRound(
      id: id,
      userId: userId,
      game: game,
      bet: bet,
      createdAt: createdAt,
      payout: payout ?? this.payout,
      multiplier: multiplier ?? this.multiplier,
      status: status ?? this.status,
      settledAt: settledAt ?? this.settledAt,
      fairness: fairness ?? this.fairness,
      details: details ?? this.details,
    );
  }

  factory GameRound.fromJson(Json json) => GameRound(
        id: parseString(json['id']) ?? '',
        userId: parseString(json['userId']) ?? '',
        game: GameType.fromName(json['game']),
        bet: parseDouble(json['bet']),
        payout: parseDouble(json['payout']),
        multiplier: parseDouble(json['multiplier']),
        status: enumByName(RoundStatus.values, json['status'], RoundStatus.pending),
        createdAt: parseDate(json['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        settledAt: parseDate(json['settledAt']),
        fairness: json['fairness'] == null ? null : FairnessProof.fromJson(parseMap(json['fairness'])),
        details: parseMap(json['details']),
      );

  Json toJson() => {
        'id': id,
        'userId': userId,
        'game': game.name,
        'bet': bet,
        'payout': payout,
        'multiplier': multiplier,
        'status': status.name,
        'createdAt': dateToMs(createdAt),
        'settledAt': dateToMs(settledAt),
        'fairness': fairness?.toJson(),
        'details': details,
      };

  factory GameRound.fromFirestore(String id, Json data) => GameRound.fromJson({...data, 'id': id});

  Json toFirestore() => {...toJson()..remove('id'), 'createdAt': createdAt, 'settledAt': settledAt};

  @override
  List<Object?> get props => [id, userId, game, bet, payout, multiplier, status, createdAt, settledAt, fairness, details];
}
