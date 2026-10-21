import '../core/api/api_client.dart';
import '../model/model_json.dart';

/// One settled bet in the feed.
class BetRow {
  const BetRow({required this.id, required this.game, required this.name, required this.bet, required this.payout, required this.multiplier, required this.win, required this.at});

  final String id;
  final String game;
  final String name;
  final double bet;
  final double payout;
  final double multiplier;
  final bool win;
  final DateTime? at;

  factory BetRow.fromJson(Map<String, dynamic> j) => BetRow(
        id: parseString(j['id']) ?? '',
        game: parseString(j['game']) ?? '',
        name: parseString(j['name']) ?? 'Guest***',
        bet: parseDouble(j['bet']),
        payout: parseDouble(j['payout']),
        multiplier: parseDouble(j['multiplier']),
        win: j['win'] == true,
        at: DateTime.tryParse(parseString(j['at']) ?? '')?.toLocal(),
      );
}

/// What players have won on one game, all time.
class TopGame {
  const TopGame({required this.game, required this.won, required this.wins});

  final String game;
  final double won;
  final int wins;

  factory TopGame.fromJson(Map<String, dynamic> j) => TopGame(game: parseString(j['game']) ?? '', won: parseDouble(j['won']), wins: parseInt(j['wins']));
}

enum BetsKind { top, mine }

class BetsApi {
  BetsApi(this._api);

  final ApiClient _api;

  /// The player's own latest bets (needs sign in). The server sends 5.
  Future<List<BetRow>> mine({required bool live}) async {
    final j = await _api.get('/v1/bets/mine?mode=${live ? 'live' : 'demo'}');
    return [for (final b in (j['bets'] as List? ?? const [])) BetRow.fromJson(parseMap(b))];
  }

  /// The games players have won the most on. Open to visitors.
  Future<List<TopGame>> top({required bool live}) async {
    final j = await _api.getOpen('/v1/bets/top?mode=${live ? 'live' : 'demo'}');
    return [for (final g in (j['games'] as List? ?? const [])) TopGame.fromJson(parseMap(g))];
  }
}
