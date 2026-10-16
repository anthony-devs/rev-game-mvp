import 'dart:math' as math;

import '../core/api/api_client.dart';
import '../model/model_json.dart';

/// The same maths as the server, so the screen can show odds before you roll.
/// The server recomputes everything and is the only source of truth.
class DiceMath {
  DiceMath._();

  static const double houseEdge = 0.03;
  static const double minTarget = 2;
  static const double maxTarget = 98;

  /// Win chance in percent. Rolls are 0.00 to 99.99, so "over" has 99.99 - target.
  static double chance(double target, bool over) => over ? _r2(99.99 - target) : _r2(target);

  static double multiplier(double chance) => (((1 - houseEdge) * 100 / chance * 10000) + 1e-9).floorToDouble() / 10000;

  static double _r2(double v) => (v * 100).roundToDouble() / 100;

  static double randomDisplay(math.Random r) => r.nextDouble() * 100;
}

class DiceResult {
  const DiceResult({
    required this.roundId,
    required this.roll,
    required this.win,
    required this.target,
    required this.over,
    required this.multiplier,
    required this.chance,
    required this.payout,
    required this.balanceAfterBet,
    required this.balance,
  });

  final String roundId;
  final double roll;
  final bool win;
  final double target;
  final bool over;
  final double multiplier;
  final double chance;
  final double payout;
  final double balanceAfterBet;
  final double balance;

  factory DiceResult.fromJson(Map<String, dynamic> j) => DiceResult(
        roundId: parseString(j['roundId']) ?? '',
        roll: parseDouble(j['roll']),
        win: j['win'] == true,
        target: parseDouble(j['target']),
        over: j['mode'] == 'over',
        multiplier: parseDouble(j['multiplier']),
        chance: parseDouble(j['chance']),
        payout: parseDouble(j['payout']),
        balanceAfterBet: parseDouble(j['balanceAfterBet']),
        balance: parseDouble(j['balance']),
      );
}

/// Dice on the game server.
class DiceApi {
  DiceApi(this._api);

  final ApiClient _api;

  Future<DiceResult> roll({required double bet, required double target, required bool over}) async {
    final j = await _api.post('/v1/dice/roll', {'bet': bet, 'target': target, 'mode': over ? 'over' : 'under'});
    return DiceResult.fromJson(j);
  }
}
