import 'package:equatable/equatable.dart';

import 'model_json.dart';

/// Virtual credits balance. Firestore path: `wallets/{uid}`.
///
/// The balance is only ever changed by the server (Cloud Function). The app reads it
/// and shows it. Never write a new balance from the client.
class Wallet extends Equatable {
  const Wallet({
    required this.userId,
    this.balance = 0,
    this.lastDailyClaimAt,
    this.updatedAt,
  });

  static const Wallet empty = Wallet(userId: '');
  static const String currency = 'credits';
  static const Duration dailyCooldown = Duration(hours: 24);

  final String userId;
  final double balance;
  final DateTime? lastDailyClaimAt;
  final DateTime? updatedAt;

  bool canAfford(double bet) => balance >= bet;

  DateTime? get nextDailyAt => lastDailyClaimAt?.add(dailyCooldown);

  bool canClaimDaily(DateTime now) {
    final next = nextDailyAt;
    return next == null || !now.isBefore(next);
  }

  /// Seconds until the next daily claim, 0 when it is ready. Feed to `formatCountdown`.
  int secondsUntilDaily(DateTime now) {
    final next = nextDailyAt;
    if (next == null || !now.isBefore(next)) return 0;
    return next.difference(now).inSeconds;
  }

  Wallet copyWith({double? balance, DateTime? lastDailyClaimAt, DateTime? updatedAt}) {
    return Wallet(
      userId: userId,
      balance: balance ?? this.balance,
      lastDailyClaimAt: lastDailyClaimAt ?? this.lastDailyClaimAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Wallet.fromJson(Json json) => Wallet(
        userId: parseString(json['userId']) ?? '',
        balance: parseDouble(json['balance']),
        lastDailyClaimAt: parseDate(json['lastDailyClaimAt']),
        updatedAt: parseDate(json['updatedAt']),
      );

  Json toJson() => {
        'userId': userId,
        'balance': balance,
        'lastDailyClaimAt': dateToMs(lastDailyClaimAt),
        'updatedAt': dateToMs(updatedAt),
      };

  factory Wallet.fromFirestore(String userId, Json data) => Wallet.fromJson({...data, 'userId': userId});

  Json toFirestore() => {
        'balance': balance,
        'lastDailyClaimAt': lastDailyClaimAt,
        'updatedAt': updatedAt,
      };

  @override
  List<Object?> get props => [userId, balance, lastDailyClaimAt, updatedAt];
}
