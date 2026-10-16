import '../core/api/api_client.dart';
import '../model/model_json.dart';

/// One bet on the table. [type] is straight, red, black, odd, even, low, high or dozen.
class RouletteBet {
  const RouletteBet(this.type, this.value, this.amount);

  final String type;
  final int? value;
  final double amount;

  String get key => value == null ? type : '$type:$value';

  /// What the bet pays in total (stake included), matching the server.
  int get returns {
    switch (type) {
      case 'straight':
        return 36;
      case 'dozen':
        return 3;
      default:
        return 2;
    }
  }

  String get name {
    switch (type) {
      case 'straight':
        return 'Number $value';
      case 'dozen':
        return value == 1 ? '1st 12' : (value == 2 ? '2nd 12' : '3rd 12');
      case 'low':
        return '1-18';
      case 'high':
        return '19-36';
      default:
        return '${type[0].toUpperCase()}${type.substring(1)}';
    }
  }

  Map<String, dynamic> toJson() => {'type': type, if (value != null) 'value': value, 'amount': amount};
}

class RouletteResult {
  const RouletteResult({
    required this.roundId,
    required this.number,
    required this.color,
    required this.totalBet,
    required this.payout,
    required this.winningKeys,
    required this.balanceAfterBet,
    required this.balance,
  });

  final String roundId;
  final int number;
  final String color;
  final double totalBet;
  final double payout;

  /// Keys (see [RouletteBet.key]) of the bets that won.
  final Set<String> winningKeys;
  final double balanceAfterBet;
  final double balance;

  double get net => payout - totalBet;

  factory RouletteResult.fromJson(Map<String, dynamic> j) {
    final keys = <String>{};
    for (final r in (j['results'] as List? ?? const [])) {
      final m = parseMap(r);
      if (m['won'] == true) {
        final v = m['value'];
        keys.add(v == null ? '${m['type']}' : '${m['type']}:${parseInt(v)}');
      }
    }
    return RouletteResult(
      roundId: parseString(j['roundId']) ?? '',
      number: parseInt(j['number']),
      color: parseString(j['color']) ?? 'green',
      totalBet: parseDouble(j['totalBet']),
      payout: parseDouble(j['payout']),
      winningKeys: keys,
      balanceAfterBet: parseDouble(j['balanceAfterBet']),
      balance: parseDouble(j['balance']),
    );
  }
}

class RouletteApi {
  RouletteApi(this._api);

  final ApiClient _api;

  Future<RouletteResult> spin(List<RouletteBet> bets) async {
    final j = await _api.post('/v1/roulette/spin', {'bets': [for (final b in bets) b.toJson()]});
    return RouletteResult.fromJson(j);
  }
}
