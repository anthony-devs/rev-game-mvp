import '../core/api/api_client.dart';
import '../model/model_json.dart';

class MinesResult {
  const MinesResult({required this.payout, required this.net, required this.multiplier, required this.label, this.hit});

  final double payout;
  final double net;
  final double multiplier;
  final String label;

  /// The tile that held a mine, when the round ended on one.
  final int? hit;

  bool get isWin => payout > 0;

  factory MinesResult.fromJson(Map<String, dynamic> j) => MinesResult(
        payout: parseDouble(j['payout']),
        net: parseDouble(j['net']),
        multiplier: parseDouble(j['multiplier']),
        label: parseString(j['label']) ?? '',
        hit: j['hit'] == null ? null : parseInt(j['hit']),
      );
}

class MinesState {
  const MinesState({
    required this.roundId,
    required this.playing,
    required this.bet,
    required this.mines,
    required this.revealed,
    required this.safeCount,
    required this.multiplier,
    required this.nextMultiplier,
    required this.cashValue,
    required this.balance,
    this.minesAt = const [],
    this.result,
  });

  final String roundId;
  final bool playing;
  final double bet;
  final int mines;
  final List<int> revealed;
  final int safeCount;
  final double multiplier;
  final double? nextMultiplier;
  final double cashValue;
  final double balance;

  /// Only sent once the round is over.
  final List<int> minesAt;
  final MinesResult? result;

  factory MinesState.fromJson(Map<String, dynamic> j) {
    List<int> ints(Object? v) => [for (final x in (v as List? ?? const [])) parseInt(x)];
    final res = j['result'];
    return MinesState(
      roundId: parseString(j['roundId']) ?? '',
      playing: j['status'] == 'playing',
      bet: parseDouble(j['bet']),
      mines: parseInt(j['mines']),
      revealed: ints(j['revealed']),
      safeCount: parseInt(j['safeCount']),
      multiplier: parseDouble(j['multiplier']),
      nextMultiplier: j['nextMultiplier'] == null ? null : parseDouble(j['nextMultiplier']),
      cashValue: parseDouble(j['cashValue']),
      balance: parseDouble(j['balance']),
      minesAt: ints(j['minesAt']),
      result: res is Map ? MinesResult.fromJson(parseMap(res)) : null,
    );
  }
}

/// A 409 from start: a round is already open. Carries that round.
class MinesResume implements Exception {
  MinesResume(this.state);
  final MinesState state;
}

class MinesApi {
  MinesApi(this._api);

  final ApiClient _api;

  Future<MinesState?> active() async {
    final j = await _api.get('/v1/mines/active');
    final s = j['active'];
    return s is Map ? MinesState.fromJson(parseMap(s)) : null;
  }

  Future<MinesState> start(double bet, int mines) async {
    try {
      return MinesState.fromJson(await _api.post('/v1/mines/start', {'bet': bet, 'mines': mines}));
    } on ApiException catch (e) {
      final s = e.data['state'];
      if (e.code == 'round_in_progress' && s is Map) throw MinesResume(MinesState.fromJson(parseMap(s)));
      rethrow;
    }
  }

  Future<MinesState> reveal(String roundId, int tile) async =>
      MinesState.fromJson(await _api.post('/v1/mines/$roundId/reveal', {'tile': tile}));

  Future<MinesState> cashOut(String roundId) async =>
      MinesState.fromJson(await _api.post('/v1/mines/$roundId/cashout', const {}));
}
