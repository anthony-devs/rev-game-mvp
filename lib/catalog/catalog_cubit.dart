import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/core/play_mode.dart';
import '../core/api/api_client.dart';
import '../core/api/rounds_hub.dart';
import '../model/model.dart';
import '../model/model_json.dart';
import '../slots_game/api_slots_server.dart';

/// Which section a game belongs to in the lobby chips.
enum GameGroup { slots, table, instant }

extension GameInfoX on GameInfo {
  /// Slots / Table / Instant, from the catalog tag.
  GameGroup get group {
    switch (tag.toLowerCase()) {
      case 'table':
        return GameGroup.table;
      case 'instant':
        return GameGroup.instant;
      default:
        return GameGroup.slots;
    }
  }
}

/// Why games can't be played right now.
enum ServiceIssue { none, maintenance, downtime, noConnection }

/// Can the app reach the game server?
enum ServerStatus { loading, online, offline }

/// What the lobby shows. The list comes from the game server (`GET /v1/games`),
/// which layers the Firestore `games` collection over its built-in list. While
/// the server can't be reached the built-in list is still shown, but [status] is
/// [ServerStatus.offline] and games are not playable:
///
/// ```
/// games/dice        { enabled: false }          -> "Game unavailable"
/// games/mines       { name: 'Mines', tag: 'Instant', comingSoon: true, type: 'dice' }
/// ```
class CatalogState extends Equatable {
  const CatalogState({this.games = defaultGames, this.status = ServerStatus.loading, this.message, this.maintenance, this.maintenanceScope = 'all', this.noConnection = false});

  final List<GameInfo> games;
  final ServerStatus status;

  /// Kept for callers that want a one-line reason. The banner uses [issue] instead.
  final String? message;

  /// True when the phone itself has no connection (not a problem on our side).
  final bool noConnection;

  bool get offline => status == ServerStatus.offline;

  /// The developer paused the app (shown to the player in words); null when running.
  final String? maintenance;
  final String maintenanceScope;

  /// Paused for the wallet being played right now ("live" pauses only live money).
  bool get paused => maintenance != null && (maintenanceScope != 'live' || PlayMode.isLive);

  /// Games can't be started: the server is unreachable or the developer paused it.
  bool get locked => offline || paused;

  /// What the player is told. Maintenance wins when the server answered and said so.
  ServiceIssue get issue {
    if (offline) return noConnection ? ServiceIssue.noConnection : ServiceIssue.downtime;
    if (paused) return ServiceIssue.maintenance;
    return ServiceIssue.none;
  }

  List<GameInfo> get playable => [for (final g in games) if (!g.comingSoon) g];
  List<GameInfo> get upcoming => [for (final g in games) if (g.comingSoon) g];

  GameInfo? byType(GameType type) {
    for (final g in games) {
      if (g.type == type && !g.comingSoon) return g;
    }
    return null;
  }

  GameInfo? byId(String id) {
    for (final g in games) {
      if (g.id == id) return g;
    }
    return null;
  }

  @override
  List<Object?> get props => [games, status, message, maintenance, maintenanceScope, noConnection];
}

const List<GameInfo> defaultGames = [
  GameInfo(id: 'slots', type: GameType.slots, name: 'Golden Reels', tag: 'Slots', minBet: 10, maxBet: 1000, rtp: .96, sortOrder: 1),
  GameInfo(id: 'crash', type: GameType.crash, name: 'Dash Crash', tag: 'Instant', minBet: 10, maxBet: 500000, rtp: .97, sortOrder: 2),
  GameInfo(id: 'roulette', type: GameType.roulette, name: 'Euro Roulette', tag: 'Table', minBet: 10, maxBet: 100000, rtp: .973, sortOrder: 3),
  GameInfo(id: 'blackjack', type: GameType.blackjack, name: 'Blackjack', tag: 'Table', minBet: 10, maxBet: 100000, rtp: .99, sortOrder: 4),
  GameInfo(id: 'dice', type: GameType.dice, name: 'Dice', tag: 'Instant', minBet: 10, maxBet: 100000, rtp: .95, sortOrder: 5),
  GameInfo(id: 'plinko', type: GameType.plinko, name: 'Plinko', tag: 'Instant', minBet: 10, maxBet: 100000, rtp: .96, sortOrder: 6),
  GameInfo(id: 'soon-lucky7', type: GameType.slots, name: 'Lucky Sevens', tag: 'Slots', comingSoon: true, sortOrder: 20),
  GameInfo(id: 'soon-fruit', type: GameType.slots, name: 'Fruit Frenzy', tag: 'Slots', comingSoon: true, sortOrder: 21),
  GameInfo(id: 'soon-diamond', type: GameType.slots, name: 'Diamond Deluxe', tag: 'Slots', comingSoon: true, sortOrder: 22),
  GameInfo(id: 'soon-mines', type: GameType.dice, name: 'Mines', tag: 'Instant', comingSoon: true, sortOrder: 23),
  GameInfo(id: 'soon-baccarat', type: GameType.blackjack, name: 'Baccarat', tag: 'Table', comingSoon: true, sortOrder: 25),
];

class CatalogCubit extends Cubit<CatalogState> {
  CatalogCubit(this._api) : super(const CatalogState());

  final ApiClient _api;
  Timer? _timer;
  bool _running = false;
  bool _busy = false;
  int _fails = 0;
  bool _warmed = false;

  /// Start loading (call after sign in) and keep the list fresh.
  void start() {
    if (_running) return;
    _running = true;
    unawaited(refresh());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _warmed = false;
    ApiSlotsServer.cached = null;
    RoundsHub.clear();
    emit(const CatalogState());
  }

  /// Ask the server now. Used by the Retry buttons.
  Future<void> refresh() async {
    if (_busy || isClosed) return;
    _busy = true;
    _timer?.cancel();
    try {
      // The status call never touches the database, so a pause or an outage is still announced
      // when Firestore is down or out of quota.
      Map<String, dynamic>? note;
      try {
        final st = await _api.get('/v1/status', timeout: const Duration(seconds: 5));
        final m = st['maintenance'];
        note = m is Map ? parseMap(m) : null;
      } on ApiException catch (e) {
        if (e.status == 401) rethrow;
      } catch (_) {}
      if (note != null) {
        _fails = 0;
        if (!isClosed) {
          emit(CatalogState(
            games: state.games,
            status: ServerStatus.online,
            maintenance: (note['message'] ?? 'Back shortly.').toString(),
            maintenanceScope: (note['scope'] ?? 'all').toString(),
          ));
        }
        return;
      }
      final json = await _api.get('/v1/games', timeout: const Duration(seconds: 6));
      final remote = [
        for (final g in (json['games'] is List ? json['games'] as List : const [])) GameInfo.fromJson(parseMap(g)),
      ];
      final byId = {for (final g in defaultGames) g.id: g};
      for (final g in remote) {
        byId[g.id] = g;
      }
      final merged = byId.values.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      _fails = 0;
      final m = json['maintenance'];
      final pause = m is Map ? parseMap(m) : null;
      if (!isClosed) {
        emit(CatalogState(
          games: merged,
          status: ServerStatus.online,
          maintenance: pause == null ? null : (pause['message'] ?? 'Back shortly.').toString(),
          maintenanceScope: (pause?['scope'] ?? 'all').toString(),
        ));
      }
      if (!_warmed) {
        // The server is up: fetch what the first game needs now, while the lobby is on screen.
        _warmed = true;
        unawaited(ApiSlotsServer.prefetch(_api));
      }
    } on ApiException catch (e) {
      _fails++;
      if (isClosed) return;
      // A 401 means the sign in is changing; don't flash a scary warning for it.
      if (e.status == 401) {
        emit(CatalogState(games: state.games, status: state.status, maintenance: state.maintenance, maintenanceScope: state.maintenanceScope));
      } else {
        emit(CatalogState(games: state.games, status: ServerStatus.offline, message: _explain(e), noConnection: e.isOffline));
      }
    } catch (_) {
      _fails++;
      if (!isClosed) emit(CatalogState(games: state.games, status: ServerStatus.offline, message: _explain(null), noConnection: false));
    } finally {
      _busy = false;
      if (_running && !isClosed) {
        // Online: re-check every 45 s. Offline: retry quickly at first, then back off.
        final wait = _fails == 0 ? (state.maintenance != null ? 15 : 45) : [3, 5, 10, 20, 30][(_fails - 1).clamp(0, 4)];
        _timer = Timer(Duration(seconds: wait), () => unawaited(refresh()));
      }
    }
  }

  /// Players never read technical words here (database, server, quota). The banner shows the
  /// calm title and body for the [ServiceIssue]; this is only a short fallback line.
  static String _explain(ApiException? e) {
    if (e == null || e.isOffline) return "Check your internet connection and try again.";
    return "We're experiencing downtime. We're working to get things back.";
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
