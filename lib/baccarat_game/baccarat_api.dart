import '../core/api/api_client.dart';
import '../model/model_json.dart';

class BaccaratResult {
  const BaccaratResult({
    required this.roundId,
    required this.player,
    required this.banker,
    required this.playerTotal,
    required this.bankerTotal,
    required this.winner,
    required this.natural,
    required this.bet,
    required this.payout,
    required this.net,
    required this.label,
    required this.balance,
  });

  final String roundId;

  /// Cards like "AS" or "10H".
  final List<String> player;
  final List<String> banker;
  final int playerTotal;
  final int bankerTotal;

  /// player, banker or tie.
  final String winner;
  final bool natural;
  final double bet;
  final double payout;
  final double net;
  final String label;
  final double balance;

  bool get isWin => net > 0;
  bool get isPush => net == 0;

  factory BaccaratResult.fromJson(Map<String, dynamic> j) {
    List<String> cards(Object? v) => [for (final c in (v as List? ?? const [])) '$c'];
    return BaccaratResult(
      roundId: parseString(j['roundId']) ?? '',
      player: cards(j['player']),
      banker: cards(j['banker']),
      playerTotal: parseInt(j['playerTotal']),
      bankerTotal: parseInt(j['bankerTotal']),
      winner: parseString(j['winner']) ?? 'tie',
      natural: j['natural'] == true,
      bet: parseDouble(j['bet']),
      payout: parseDouble(j['payout']),
      net: parseDouble(j['net']),
      label: parseString(j['label']) ?? '',
      balance: parseDouble(j['balance']),
    );
  }
}

class BaccaratApi {
  BaccaratApi(this._api);

  final ApiClient _api;

  Future<BaccaratResult> play(Map<String, double> bets) async =>
      BaccaratResult.fromJson(await _api.post('/v1/baccarat/play', {'bets': bets}));
}
