import '../core/api/api_client.dart';
import '../model/model_json.dart';

class KenoConfig {
  const KenoConfig({required this.minBet, required this.maxBet, required this.pool, required this.maxPicks, required this.tables});

  final double minBet;
  final double maxBet;
  final int pool;
  final int maxPicks;

  /// For each number of picks, the multiplier by number of hits (index = hits).
  final Map<int, List<double>> tables;

  factory KenoConfig.fromJson(Map<String, dynamic> j) {
    final t = parseMap(j['tables']);
    return KenoConfig(
      minBet: parseDouble(j['minBet']),
      maxBet: parseDouble(j['maxBet']),
      pool: parseInt(j['pool']),
      maxPicks: parseInt(j['maxPicks']),
      tables: {for (final e in t.entries) int.parse(e.key): [for (final x in (e.value as List)) parseDouble(x)]},
    );
  }
}

class KenoResult {
  const KenoResult({
    required this.roundId,
    required this.picks,
    required this.drawn,
    required this.hits,
    required this.multiplier,
    required this.bet,
    required this.payout,
    required this.net,
    required this.balance,
  });

  final String roundId;
  final List<int> picks;
  final List<int> drawn;
  final List<int> hits;
  final double multiplier;
  final double bet;
  final double payout;
  final double net;
  final double balance;

  bool get isWin => payout > bet;
  bool get isPush => payout == bet;
}

class KenoApi {
  KenoApi(this._api);

  final ApiClient _api;

  Future<KenoConfig> config() async => KenoConfig.fromJson(await _api.get('/v1/keno/config'));

  Future<KenoResult> play(double bet, List<int> picks) async {
    final j = await _api.post('/v1/keno/play', {'bet': bet, 'picks': picks});
    List<int> ints(Object? v) => [for (final x in (v as List? ?? const [])) parseInt(x)];
    return KenoResult(
      roundId: parseString(j['roundId']) ?? '',
      picks: ints(j['picks']),
      drawn: ints(j['drawn']),
      hits: ints(j['hits']),
      multiplier: parseDouble(j['multiplier']),
      bet: bet,
      payout: parseDouble(j['payout']),
      net: parseDouble(j['net']),
      balance: parseDouble(j['balance']),
    );
  }
}
