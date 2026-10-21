import '../core/api/api_client.dart';
import '../model/model_json.dart';

const List<int> plinkoRows = [8, 10, 12, 14, 16];

enum PlinkoRisk {
  low('low', 'Low'),
  medium('medium', 'Medium'),
  high('high', 'High');

  const PlinkoRisk(this.id, this.label);
  final String id;
  final String label;
}

/// The board the server will use for the wallet being played (demo and live pay differently).
/// Multipliers come from the server and are never calculated on the phone.
class PlinkoQuote {
  const PlinkoQuote({required this.rows, required this.risk, required this.multipliers, required this.rtp, required this.minBet, required this.maxBet});

  final int rows;
  final PlinkoRisk risk;

  /// One per slot, left to right (`rows + 1` of them).
  final List<double> multipliers;
  final double rtp;
  final double minBet;

  /// Highest bet allowed on this board (the top multiplier is limited by a payout cap).
  final double maxBet;

  double get top => multipliers.isEmpty ? 0 : multipliers.reduce((a, b) => a > b ? a : b);

  factory PlinkoQuote.fromJson(Map<String, dynamic> j) => PlinkoQuote(
        rows: parseInt(j['rows'], 12),
        risk: PlinkoRisk.values.firstWhere((r) => r.id == j['risk'], orElse: () => PlinkoRisk.medium),
        multipliers: [for (final m in (j['multipliers'] is List ? j['multipliers'] as List : const [])) parseDouble(m)],
        rtp: parseDouble(j['rtp']),
        minBet: parseDouble(j['minBet'], 10),
        maxBet: parseDouble(j['maxBet'], 2000),
      );
}

class PlinkoResult {
  const PlinkoResult({
    required this.roundId,
    required this.path,
    required this.slot,
    required this.multiplier,
    required this.win,
    required this.payout,
    required this.balanceAfterBet,
    required this.balance,
    required this.rows,
  });

  final String roundId;

  /// 0 = left, 1 = right at each row. The ball follows exactly this path.
  final List<int> path;
  final int slot;
  final double multiplier;
  final bool win;
  final double payout;
  final double balanceAfterBet;
  final double balance;
  final int rows;

  factory PlinkoResult.fromJson(Map<String, dynamic> j) {
    final path = [for (final p in (j['path'] is List ? j['path'] as List : const [])) parseInt(p)];
    return PlinkoResult(
      roundId: parseString(j['roundId']) ?? '',
      path: path,
      slot: parseInt(j['slot']),
      multiplier: parseDouble(j['multiplier']),
      win: j['win'] == true,
      payout: parseDouble(j['payout']),
      balanceAfterBet: parseDouble(j['balanceAfterBet']),
      balance: parseDouble(j['balance']),
      rows: parseInt(j['rows'], path.length),
    );
  }
}

class PlinkoApi {
  PlinkoApi(this._api);

  final ApiClient _api;

  Future<PlinkoQuote> quote(int rows, PlinkoRisk risk) async =>
      PlinkoQuote.fromJson(await _api.get('/v1/plinko/quote?rows=$rows&risk=${risk.id}', timeout: const Duration(seconds: 8)));

  Future<PlinkoResult> drop({required double bet, required int rows, required PlinkoRisk risk}) async =>
      PlinkoResult.fromJson(await _api.post('/v1/plinko/drop', {'bet': bet, 'rows': rows, 'risk': risk.id}));
}
