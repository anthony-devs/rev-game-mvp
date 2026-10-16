import 'package:equatable/equatable.dart';

import 'game_type.dart';
import 'model_json.dart';

enum TransactionType { bet, win, topUp, dailyReward, adjustment }

/// One line of the wallet ledger. Firestore path: `wallets/{uid}/transactions/{id}`.
///
/// [amount] is signed: a bet is negative, a win or reward is positive.
class WalletTransaction extends Equatable {
  const WalletTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.createdAt,
    this.game,
    this.roundId,
  });

  final String id;
  final String userId;
  final TransactionType type;
  final double amount;
  final double balanceAfter;
  final DateTime createdAt;
  final GameType? game;
  final String? roundId;

  bool get isCredit => amount > 0;

  factory WalletTransaction.fromJson(Json json) => WalletTransaction(
        id: parseString(json['id']) ?? '',
        userId: parseString(json['userId']) ?? '',
        type: enumByName(TransactionType.values, json['type'], TransactionType.adjustment),
        amount: parseDouble(json['amount']),
        balanceAfter: parseDouble(json['balanceAfter']),
        createdAt: parseDate(json['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        game: json['game'] == null ? null : GameType.fromName(json['game']),
        roundId: parseString(json['roundId']),
      );

  Json toJson() => {
        'id': id,
        'userId': userId,
        'type': type.name,
        'amount': amount,
        'balanceAfter': balanceAfter,
        'createdAt': dateToMs(createdAt),
        'game': game?.name,
        'roundId': roundId,
      };

  factory WalletTransaction.fromFirestore(String id, Json data) => WalletTransaction.fromJson({...data, 'id': id});

  Json toFirestore() => {...toJson()..remove('id'), 'createdAt': createdAt};

  @override
  List<Object?> get props => [id, userId, type, amount, balanceAfter, createdAt, game, roundId];
}
