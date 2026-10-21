import '../core/api/api_client.dart';
import '../model/model_json.dart';

class EventMe {
  const EventMe({required this.rank, required this.score, required this.prize});

  final int rank;
  final double score;
  final double prize;

  factory EventMe.fromJson(Map<String, dynamic> j) => EventMe(rank: parseInt(j['rank']), score: parseDouble(j['score']), prize: parseDouble(j['prize']));
}

class BoardRow {
  const BoardRow({required this.rank, required this.name, required this.score, required this.prize, required this.me});

  final int rank;
  final String name;
  final double score;
  final double prize;
  final bool me;

  factory BoardRow.fromJson(Map<String, dynamic> j) => BoardRow(
        rank: parseInt(j['rank']),
        name: parseString(j['name']) ?? 'Guest***',
        score: parseDouble(j['score']),
        prize: parseDouble(j['prize']),
        me: j['me'] == true,
      );
}

class GameEvent {
  const GameEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.kind,
    required this.kindName,
    required this.live,
    required this.game,
    required this.startsAt,
    required this.endsAt,
    required this.minBet,
    required this.prizes,
    required this.status,
    this.me,
    this.board = const [],
    this.players = 0,
    this.boostMult,
    this.boostMinutes = 0,
    this.boostClaimed = false,
  });

  final String id;
  final String title;
  final String description;
  final String kind;
  final String kindName;
  final bool live;
  final String? game;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final double minBet;
  final List<double> prizes;

  /// upcoming, live, ended or settled.
  final String status;
  final EventMe? me;
  final List<BoardRow> board;
  final int players;

  /// A bonus multiplier players can claim while the event runs (null when the event has none).
  final double? boostMult;
  final int boostMinutes;
  final bool boostClaimed;

  bool get running => status == 'live';
  bool get finished => status == 'ended' || status == 'settled';

  /// How the score is written: money for wagers and wins, a multiplier for the hunt.
  bool get scoreIsMultiplier => kind == 'multiplier';

  factory GameEvent.fromJson(Map<String, dynamic> j) {
    final me = j['me'];
    return GameEvent(
      id: parseString(j['id']) ?? '',
      title: parseString(j['title']) ?? '',
      description: parseString(j['description']) ?? '',
      kind: parseString(j['kind']) ?? 'wager',
      kindName: parseString(j['kindName']) ?? '',
      live: j['mode'] == 'live',
      game: parseString(j['game']),
      startsAt: DateTime.tryParse(parseString(j['startsAt']) ?? '')?.toLocal(),
      endsAt: DateTime.tryParse(parseString(j['endsAt']) ?? '')?.toLocal(),
      minBet: parseDouble(j['minBet']),
      prizes: [for (final p in (j['prizes'] as List? ?? const [])) parseDouble(p)],
      status: parseString(j['status']) ?? 'live',
      me: me is Map ? EventMe.fromJson(parseMap(me)) : null,
      board: [for (final b in (j['board'] as List? ?? const [])) BoardRow.fromJson(parseMap(b))],
      players: parseInt(j['players']),
      boostMult: j['boost'] is Map ? parseDouble(parseMap(j['boost'])['mult']) : null,
      boostMinutes: j['boost'] is Map ? parseInt(parseMap(j['boost'])['minutes']) : 0,
      boostClaimed: j['boostClaimed'] == true,
    );
  }
}

class EventsApi {
  EventsApi(this._api);

  final ApiClient _api;

  Future<List<GameEvent>> list({required bool live}) async {
    final j = await _api.getOpen('/v1/events?mode=${live ? 'live' : 'demo'}');
    return [for (final e in (j['events'] as List? ?? const [])) GameEvent.fromJson(parseMap(e))];
  }

  Future<GameEvent> get(String id) async => GameEvent.fromJson(await _api.getOpen('/v1/events/$id'));

  /// Claims the event's bonus multiplier.
  Future<void> claimBoost(String id) async {
    await _api.post('/v1/events/$id/boost');
  }
}
