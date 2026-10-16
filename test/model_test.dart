import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rev_game_mvp/model/model.dart';

void main() {
  test('AppUser survives a JSON round trip', () {
    final user = AppUser(
      id: 'u1',
      displayName: 'Anthony',
      email: 'a@b.com',
      ageConfirmed: true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    final back = AppUser.fromJson(jsonDecode(jsonEncode(user.toJson())) as Map<String, dynamic>);
    expect(back, user);
    expect(back.canPlay, isTrue);
  });

  test('unknown enum values fall back instead of throwing', () {
    final user = AppUser.fromJson({'id': 'u1', 'status': 'something_new'});
    expect(user.status, UserStatus.active);
    expect(GameType.fromName('keno'), GameType.slots);
  });

  test('Wallet daily claim', () {
    final now = DateTime(2026, 10, 16, 12);
    final claimed = Wallet(userId: 'u1', balance: 100, lastDailyClaimAt: now.subtract(const Duration(hours: 3)));
    expect(claimed.canClaimDaily(now), isFalse);
    expect(claimed.secondsUntilDaily(now), 21 * 3600);
    expect(const Wallet(userId: 'u1').canClaimDaily(now), isTrue);
  });

  test('GameRound net and nested fairness round trip', () {
    final round = GameRound(
      id: 'r1',
      userId: 'u1',
      game: GameType.crash,
      bet: 100,
      payout: 342,
      multiplier: 3.42,
      status: RoundStatus.cashedOut,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      fairness: const FairnessProof(serverSeedHash: 'abc', serverSeed: 'xyz', clientSeed: 'c', nonce: 4),
      details: const {'crashPoint': 4.87},
    );
    expect(round.net, 242);
    expect(round.isWin, isTrue);
    expect(GameRound.fromJson(jsonDecode(jsonEncode(round.toJson())) as Map<String, dynamic>), round);
  });

  test('CacheEntry expiry', () {
    final entry = CacheEntry<int>(data: 1, cachedAt: DateTime(2026, 1, 1), ttl: const Duration(hours: 1));
    expect(entry.isExpired(DateTime(2026, 1, 1, 0, 59)), isFalse);
    expect(entry.isExpired(DateTime(2026, 1, 1, 1)), isTrue);
  });

  test('parseDate reads ms, ISO strings and Timestamp-like objects', () {
    expect(parseDate(1700000000000), DateTime.fromMillisecondsSinceEpoch(1700000000000));
    expect(parseDate('2026-10-16T00:00:00.000'), DateTime(2026, 10, 16));
    expect(parseDate(_FakeTimestamp(DateTime(2026, 10, 16))), DateTime(2026, 10, 16));
    expect(parseDate(null), isNull);
  });
}

class _FakeTimestamp {
  _FakeTimestamp(this._d);
  final DateTime _d;
  DateTime toDate() => _d;
}
