import '../core/api/api_client.dart';
import '../model/model_json.dart';

class HiLoOption {
  const HiLoOption({required this.chance, required this.multiplier});

  final double chance;

  /// Null when this guess cannot win.
  final double? multiplier;

  bool get available => multiplier != null && chance > 0;

  factory HiLoOption.fromJson(Object? v) {
    final j = v is Map ? parseMap(v) : const <String, dynamic>{};
    return HiLoOption(chance: parseDouble(j['chance']), multiplier: j['multiplier'] == null ? null : parseDouble(j['multiplier']));
  }
}

class HiLoResult {
  const HiLoResult({required this.payout, required this.net, required this.multiplier, required this.label, required this.lost});

  final double payout;
  final double net;
  final double multiplier;
  final String label;
  final bool lost;

  factory HiLoResult.fromJson(Map<String, dynamic> j) => HiLoResult(
        payout: parseDouble(j['payout']),
        net: parseDouble(j['net']),
        multiplier: parseDouble(j['multiplier']),
        label: parseString(j['label']) ?? '',
        lost: j['lost'] == true,
      );
}

class HiLoState {
  const HiLoState({
    required this.roundId,
    required this.playing,
    required this.bet,
    required this.card,
    required this.history,
    required this.correct,
    required this.multiplier,
    required this.balance,
    required this.higher,
    required this.lower,
    required this.cashValue,
    this.result,
  });

  final String roundId;
  final bool playing;
  final double bet;
  final String card;
  final List<String> history;
  final int correct;
  final double multiplier;
  final double balance;
  final HiLoOption higher;
  final HiLoOption lower;
  final double cashValue;
  final HiLoResult? result;

  factory HiLoState.fromJson(Map<String, dynamic> j) {
    final res = j['result'];
    return HiLoState(
      roundId: parseString(j['roundId']) ?? '',
      playing: j['status'] == 'playing',
      bet: parseDouble(j['bet']),
      card: parseString(j['card']) ?? '',
      history: [for (final x in (j['history'] as List? ?? const [])) x.toString()],
      correct: parseInt(j['correct']),
      multiplier: parseDouble(j['multiplier']),
      balance: parseDouble(j['balance']),
      higher: HiLoOption.fromJson(j['higher']),
      lower: HiLoOption.fromJson(j['lower']),
      cashValue: parseDouble(j['cashValue']),
      result: res is Map ? HiLoResult.fromJson(parseMap(res)) : null,
    );
  }
}

/// A 409 from start: a round is already open. Carries that round.
class HiLoResume implements Exception {
  HiLoResume(this.state);
  final HiLoState state;
}

class HiLoApi {
  HiLoApi(this._api);

  final ApiClient _api;

  Future<HiLoState?> active() async {
    final j = await _api.get('/v1/hilo/active');
    final s = j['active'];
    return s is Map ? HiLoState.fromJson(parseMap(s)) : null;
  }

  Future<HiLoState> start(double bet) async {
    try {
      return HiLoState.fromJson(await _api.post('/v1/hilo/start', {'bet': bet}));
    } on ApiException catch (e) {
      final s = e.data['state'];
      if (e.code == 'round_in_progress' && s is Map) throw HiLoResume(HiLoState.fromJson(parseMap(s)));
      rethrow;
    }
  }

  Future<HiLoState> guess(String roundId, String choice) async =>
      HiLoState.fromJson(await _api.post('/v1/hilo/$roundId/guess', {'choice': choice}));

  Future<HiLoState> cashOut(String roundId) async =>
      HiLoState.fromJson(await _api.post('/v1/hilo/$roundId/cashout', const {}));
}
