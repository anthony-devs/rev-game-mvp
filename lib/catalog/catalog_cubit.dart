import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/api/api_client.dart';
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

/// Can the app reach the game server?
enum ServerStatus { loading, online, offline }

/// What the lobby shows. The list comes from the game server (`GET /v1/games`),
/// which layers the Firestore `games` collection over its built-in list. While
/// the server can't be reached the built-in list is still shown, but [status] is
/// [ServerStatus.offline] and games are not playable:
///
/// ```
/// games/dice        { enabled: false }          -> "Game unavailable"
/// games/plinko      { name: 'Plinko', tag: 'Instant', comingSoon: true, type: 'dice' }
/// ```
class CatalogState extends Equatable {
  const CatalogState({this.games = defaultGames, this.status = ServerStatus.loading, this.message});

  final List<GameInfo> games;
  final ServerStatus status;

  /// Why the server is unreachable, in words the player can read.
  final String? message;

  bool get offline => status == ServerStatus.offline;

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
  List<Object?> get props => [games, status, message];
}

const List<GameInfo> defaultGames = [
  GameInfo(id: 'slots', type: GameType.slots, name: 'Golden Reels', tag: 'Slots', minBet: 10, maxBet: 1000, rtp: .96, sortOrder: 1),
  GameInfo(id: 'crash', type: GameType.crash, name: 'Dash Crash', tag: 'Instant', minBet: 10, maxBet: 500000, rtp: .97, sortOrder: 2),
  GameInfo(id: 'roulette', type: GameType.roulette, name: 'Euro Roulette', tag: 'Table', minBet: 10, maxBet: 100000, rtp: .973, sortOrder: 3),
  GameInfo(id: 'blackjack', type: GameType.blackjack, name: 'Blackjack', tag: 'Table', minBet: 10, maxBet: 100000, rtp: .99, sortOrder: 4),
  GameInfo(id: 'dice', type: GameType.dice, name: 'Dice', tag: 'Instant', minBet: 10, maxBet: 100000, rtp: .95, sortOrder: 5),
  GameInfo(id: 'soon-lucky7', type: GameType.slots, name: 'Lucky Sevens', tag: 'Slots', comingSoon: true, sortOrder: 20),
  GameInfo(id: 'soon-fruit', type: GameType.slots, name: 'Fruit Frenzy', tag: 'Slots', comingSoon: true, sortOrder: 21),
  GameInfo(id: 'soon-diamond', type: GameType.slots, name: 'Diamond Deluxe', tag: 'Slots', comingSoon: true, sortOrder: 22),
  GameInfo(id: 'soon-mines', type: GameType.dice, name: 'Mines', tag: 'Instant', comingSoon: true, sortOrder: 23),
  GameInfo(id: 'soon-plinko', type: GameType.dice, name: 'Plinko', tag: 'Instant', comingSoon: true, sortOrder: 24),
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
    emit(const CatalogState());
  }

  /// Ask the server now. Used by the Retry buttons.
  Future<void> refresh() async {
    if (_busy || isClosed) return;
    _busy = true;
    _timer?.cancel();
    try {
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
      if (!isClosed) emit(CatalogState(games: merged, status: ServerStatus.online));
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
        emit(CatalogState(games: state.games, status: state.status));
      } else {
        emit(CatalogState(games: state.games, status: ServerStatus.offline, message: _explain(e)));
      }
    } catch (_) {
      _fails++;
      if (!isClosed) emit(CatalogState(games: state.games, status: ServerStatus.offline, message: _explain(null)));
    } finally {
      _busy = false;
      if (_running && !isClosed) {
        // Online: re-check every 45 s. Offline: retry quickly at first, then back off.
        final wait = _fails == 0 ? 45 : [3, 5, 10, 20, 30][(_fails - 1).clamp(0, 4)];
        _timer = Timer(Duration(seconds: wait), () => unawaited(refresh()));
      }
    }
  }

  static String _explain(ApiException? e) {
    if (e == null || e.isNetwork) return "Can't reach the game server. Check your connection, or the server may be down.";
    if (e.code == 'not_initialized') return "The game server is up but its database isn't set up yet.";
    if (e.status >= 500) return 'The game server is having trouble right now.';
    return e.message;
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
