import '../core/api/api_client.dart';
import '../model/model_json.dart';

class WheelConfig {
  const WheelConfig({required this.minBet, required this.maxBet, required this.segments});

  final double minBet;
  final double maxBet;

  /// Multiplier of every segment, in wheel order, for each risk level.
  final Map<String, List<double>> segments;

  factory WheelConfig.fromJson(Map<String, dynamic> j) {
    final seg = parseMap(j['segments']);
    return WheelConfig(
      minBet: parseDouble(j['minBet']),
      maxBet: parseDouble(j['maxBet']),
      segments: {
        for (final e in seg.entries) e.key: [for (final x in (e.value as List)) parseDouble(x)],
      },
    );
  }
}

class WheelResult {
  const WheelResult({
    required this.roundId,
    required this.risk,
    required this.index,
    required this.segments,
    required this.multiplier,
    required this.bet,
    required this.payout,
    required this.net,
    required this.balance,
  });

  final String roundId;
  final String risk;
  final int index;
  final List<double> segments;
  final double multiplier;
  final double bet;
  final double payout;
  final double net;
  final double balance;

  bool get isWin => payout > bet;
  bool get isPush => payout == bet;
}

class WheelApi {
  WheelApi(this._api);

  final ApiClient _api;

  Future<WheelConfig> config() async => WheelConfig.fromJson(await _api.get('/v1/wheel/config'));

  Future<WheelResult> spin(double bet, String risk) async {
    final j = await _api.post('/v1/wheel/spin', {'bet': bet, 'risk': risk});
    final payout = parseDouble(j['payout']);
    return WheelResult(
      roundId: parseString(j['roundId']) ?? '',
      risk: parseString(j['risk']) ?? risk,
      index: parseInt(j['index']),
      segments: [for (final x in (j['segments'] as List)) parseDouble(x)],
      multiplier: parseDouble(j['multiplier']),
      bet: bet,
      payout: payout,
      net: parseDouble(j['net']),
      balance: parseDouble(j['balance']),
    );
  }
}
