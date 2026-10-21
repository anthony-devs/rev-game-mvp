import '../core/api/api_client.dart';
import '../model/model_json.dart';

/// What the server says about one arcade game: limits, odds and (for climbing games) the difficulty ladders.
class ArcadeConfig {
  const ArcadeConfig(this.raw);

  final Map<String, dynamic> raw;

  double get minBet => parseDouble(raw['minBet']);
  double get maxBet => parseDouble(raw['maxBet']);
  double get edge => parseDouble(raw['edge']);
  double get multiplier => parseDouble(raw['multiplier']);
  double get minTarget => parseDouble(raw['minTarget'], 1.01);
  double get maxTarget => parseDouble(raw['maxTarget'], 1000);

  List<String> get risks => [for (final r in (raw['risks'] as List? ?? const [])) '$r'];

  List<double> segments(String risk) => [for (final x in ((parseMap(raw['segments'])[risk]) as List? ?? const [])) parseDouble(x)];

  List<(List<int>, double)> get pays => [
        for (final p in (raw['pays'] as List? ?? const []))
          ([for (final c in (parseMap(p)['pattern'] as List)) parseInt(c)], parseDouble(parseMap(p)['multiplier']))
      ];

  /// In the order the server sends them (easy first). JSON objects are not ordered, so there is a separate list.
  List<String> get difficulties {
    final order = [for (final d in (raw['order'] as List? ?? const [])) '$d'];
    return order.isNotEmpty ? order : parseMap(raw['difficulties']).keys.toList();
  }

  LadderLevels levels(String difficulty) {
    final d = parseMap(parseMap(raw['difficulties'])[difficulty]);
    return LadderLevels(
      cols: [for (final x in (d['cols'] as List? ?? const [])) parseInt(x)],
      bad: [for (final x in (d['bad'] as List? ?? const [])) parseInt(x)],
      multipliers: [for (final x in (d['multipliers'] as List? ?? const [])) parseDouble(x)],
    );
  }
}

class LadderLevels {
  const LadderLevels({required this.cols, required this.bad, required this.multipliers});

  final List<int> cols;
  final List<int> bad;
  final List<double> multipliers;
}

/// The result of one instant round.
class ArcadeResult {
  const ArcadeResult({
    required this.roundId,
    required this.multiplier,
    required this.payout,
    required this.net,
    required this.balance,
    required this.label,
    required this.bet,
    required this.detail,
  });

  final String roundId;
  final double multiplier;
  final double payout;
  final double net;
  final double balance;
  final String label;
  final double bet;
  final Map<String, dynamic> detail;

  bool get isWin => payout > bet;
  bool get isPush => payout == bet;
}

class LadderResult {
  const LadderResult({required this.payout, required this.net, required this.multiplier, required this.label, required this.hit});

  final double payout;
  final double net;
  final double multiplier;
  final String label;
  final bool hit;

  bool get isWin => payout > 0;
}

class LadderState {
  const LadderState({
    required this.roundId,
    required this.playing,
    required this.bet,
    required this.difficulty,
    required this.cols,
    required this.picks,
    required this.safeCount,
    required this.multiplier,
    required this.multipliers,
    required this.cashValue,
    required this.balance,
    this.badMask = const [],
    this.result,
  });

  final String roundId;
  final bool playing;
  final double bet;
  final String difficulty;
  final List<int> cols;
  final List<int> picks;
  final int safeCount;
  final double multiplier;
  final List<double> multipliers;
  final double cashValue;
  final double balance;

  /// One bit per choice, for every level. Only sent when the round is over.
  final List<int> badMask;
  final LadderResult? result;

  int get levels => cols.length;
  int get level => playing ? picks.length : safeCount;

  factory LadderState.fromJson(Map<String, dynamic> j) {
    List<int> ints(Object? v) => [for (final x in (v as List? ?? const [])) parseInt(x)];
    final res = j['result'];
    return LadderState(
      roundId: parseString(j['roundId']) ?? '',
      playing: j['status'] == 'playing',
      bet: parseDouble(j['bet']),
      difficulty: parseString(j['difficulty']) ?? '',
      cols: ints(j['cols']),
      picks: ints(j['picks']),
      safeCount: parseInt(j['safeCount']),
      multiplier: parseDouble(j['multiplier']),
      multipliers: [for (final x in (j['multipliers'] as List? ?? const [])) parseDouble(x)],
      cashValue: parseDouble(j['cashValue']),
      balance: parseDouble(j['balance']),
      badMask: ints(j['badMask']),
      result: res is Map
          ? LadderResult(
              payout: parseDouble(res['payout']),
              net: parseDouble(res['net']),
              multiplier: parseDouble(res['multiplier']),
              label: parseString(res['label']) ?? '',
              hit: res['hit'] == true,
            )
          : null,
    );
  }
}

/// A 409 from start: a round is already open. Carries that round.
class LadderResume implements Exception {
  LadderResume(this.state);
  final LadderState state;
}

class ArcadeApi {
  ArcadeApi(this._api, this.game);

  final ApiClient _api;
  final String game;

  Future<ArcadeConfig> config() async => ArcadeConfig(await _api.get('/v1/arcade/$game/config'));

  Future<ArcadeResult> play(double bet, Map<String, dynamic> choice) async {
    final j = await _api.post('/v1/arcade/$game/play', {'bet': bet, ...choice});
    return ArcadeResult(
      roundId: parseString(j['roundId']) ?? '',
      multiplier: parseDouble(j['multiplier']),
      payout: parseDouble(j['payout']),
      net: parseDouble(j['net']),
      balance: parseDouble(j['balance']),
      label: parseString(j['label']) ?? '',
      bet: bet,
      detail: parseMap(j['result']),
    );
  }

  Future<LadderState?> active() async {
    final j = await _api.get('/v1/arcade/$game/active');
    final s = j['active'];
    return s is Map ? LadderState.fromJson(parseMap(s)) : null;
  }

  Future<LadderState> start(double bet, String difficulty) async {
    try {
      return LadderState.fromJson(await _api.post('/v1/arcade/$game/start', {'bet': bet, 'difficulty': difficulty}));
    } on ApiException catch (e) {
      final s = e.data['state'];
      if (e.code == 'round_in_progress' && s is Map) throw LadderResume(LadderState.fromJson(parseMap(s)));
      rethrow;
    }
  }

  Future<LadderState> step(String roundId, int pick) async =>
      LadderState.fromJson(await _api.post('/v1/arcade/$game/$roundId/step', {'pick': pick}));

  Future<LadderState> cashOut(String roundId) async =>
      LadderState.fromJson(await _api.post('/v1/arcade/$game/$roundId/cashout', const {}));
}
