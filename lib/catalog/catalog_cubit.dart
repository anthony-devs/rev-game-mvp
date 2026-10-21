import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/core/play_mode.dart';
import '../core/api/api_cache.dart';
import '../core/api/api_client.dart';
import '../core/api/rounds_hub.dart';
import '../model/model.dart';
import '../model/model_json.dart';
import '../slots_game/api_slots_server.dart';

/// A home screen section as the server describes it.
class GameGroupInfo extends Equatable {
  const GameGroupInfo(this.id, this.name);

  final String id;
  final String name;

  @override
  List<Object?> get props => [id, name];
}

/// Shown until the server answers (and when it cannot be reached).
const List<GameGroupInfo> defaultGroups = [
  GameGroupInfo('originals', 'Originals'),
  GameGroupInfo('crash', 'Crash Games'),
  GameGroupInfo('adventure', 'Pick and Climb'),
  GameGroupInfo('table', 'Table Games'),
  GameGroupInfo('slots', 'Slots'),
  GameGroupInfo('quick', 'Quick Wins'),
];

/// Why games can't be played right now.
enum ServiceIssue { none, maintenance, downtime, noConnection, slowConnection, unreachable }

/// Can the app reach the game server?
enum ServerStatus { loading, online, offline }

/// What the lobby shows. The list comes from the game server (`GET /v1/games`),
/// which layers the Firestore `games` collection over its built-in list. While
/// the server can't be reached the built-in list is still shown, but [status] is
/// [ServerStatus.offline] and games are not playable:
///
/// ```
/// games/dice        { enabled: false }          -> "Game unavailable"
/// games/mines       { name: 'Mines', tag: 'Instant', rtp: 0.96 }
/// ```
class CatalogState extends Equatable {
  const CatalogState({this.games = defaultGames, this.status = ServerStatus.loading, this.message, this.maintenance, this.maintenanceScope = 'all', this.noConnection = false, this.slow = false, this.unreachable = false, this.groups = defaultGroups, this.popular = const ['crash', 'mines', 'slots']});

  final List<GameInfo> games;
  final ServerStatus status;

  /// Kept for callers that want a one-line reason. The banner uses [issue] instead.
  final String? message;

  /// True when the phone itself has no connection (not a problem on our side).
  final bool noConnection;

  /// The phone is online but the answer was too slow to arrive (a weak connection).
  final bool slow;

  /// The phone is online but could not connect to the service at all.
  final bool unreachable;

  /// The home screen sections, in order, and the (at most three) popular game ids.
  final List<GameGroupInfo> groups;
  final List<String> popular;

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
    if (offline) {
      if (noConnection) return ServiceIssue.noConnection;
      if (slow) return ServiceIssue.slowConnection;
      if (unreachable) return ServiceIssue.unreachable;
      return ServiceIssue.downtime; // our service answered that it is down
    }
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
  List<Object?> get props => [games, status, message, maintenance, maintenanceScope, noConnection, slow, unreachable, groups, popular];
}

const List<GameInfo> defaultGames = [
  GameInfo(id: 'slots', type: GameType.slots, name: 'Golden Reels', tag: 'Slots', group: 'slots', minBet: 10, maxBet: 500, rtp: .96, sortOrder: 1),
  GameInfo(id: 'crash', type: GameType.crash, name: 'Dash Crash', tag: 'Instant', group: 'crash', minBet: 10, maxBet: 2000, rtp: .97, sortOrder: 2),
  GameInfo(id: 'roulette', type: GameType.roulette, name: 'Euro Roulette', tag: 'Table', group: 'table', minBet: 10, maxBet: 5000, rtp: .973, sortOrder: 3),
  GameInfo(id: 'blackjack', type: GameType.blackjack, name: 'Blackjack', tag: 'Table', group: 'table', minBet: 10, maxBet: 2000, rtp: .99, sortOrder: 4),
  GameInfo(id: 'dice', type: GameType.dice, name: 'Dice', tag: 'Instant', group: 'originals', minBet: 10, maxBet: 2000, rtp: .95, sortOrder: 5),
  GameInfo(id: 'plinko', type: GameType.plinko, name: 'Plinko', tag: 'Instant', group: 'originals', minBet: 10, maxBet: 2000, rtp: .96, sortOrder: 6),
  GameInfo(id: 'lucky7', type: GameType.slots, name: 'Lucky Sevens', tag: 'Slots', group: 'slots', minBet: 10, maxBet: 500, rtp: .96, sortOrder: 7),
  GameInfo(id: 'mines', type: GameType.mines, name: 'Mines', tag: 'Instant', group: 'adventure', minBet: 10, maxBet: 2000, rtp: .96, sortOrder: 8),
  GameInfo(id: 'baccarat', type: GameType.baccarat, name: 'Baccarat', tag: 'Table', group: 'table', minBet: 10, maxBet: 5000, rtp: .9894, sortOrder: 9),
  GameInfo(id: 'wheel', type: GameType.wheel, name: 'Lucky Wheel', tag: 'Instant', group: 'originals', minBet: 10, maxBet: 2000, rtp: .96, sortOrder: 10),
  GameInfo(id: 'keno', type: GameType.keno, name: 'Keno', tag: 'Instant', group: 'originals', minBet: 10, maxBet: 2000, rtp: .96, sortOrder: 11),
  GameInfo(id: 'hilo', type: GameType.hilo, name: 'Hi-Lo', tag: 'Instant', group: 'originals', minBet: 10, maxBet: 2000, rtp: .96, sortOrder: 12),
  GameInfo(id: 'limbo', type: GameType.limbo, name: 'Limbo', tag: 'Instant', group: 'originals', minBet: 10, maxBet: 2000, rtp: .96, sortOrder: 13),
  GameInfo(id: 'darts', type: GameType.darts, name: 'Darts', tag: 'Instant', group: 'originals', minBet: 10, maxBet: 2000, rtp: .96, sortOrder: 14),
  GameInfo(id: 'diamonds', type: GameType.diamonds, name: 'Diamonds', tag: 'Instant', group: 'originals', minBet: 10, maxBet: 2000, rtp: .96, sortOrder: 15),
  GameInfo(id: 'coinflip', type: GameType.coinflip, name: 'Coin Flip', tag: 'Quick', group: 'quick', minBet: 10, maxBet: 2000, rtp: .96, sortOrder: 16),
  GameInfo(id: 'rps', type: GameType.rps, name: 'Rock Paper Scissors', tag: 'Quick', group: 'quick', minBet: 10, maxBet: 2000, rtp: .96, sortOrder: 17),
  GameInfo(id: 'scratch', type: GameType.scratch, name: 'Scratch Card', tag: 'Quick', group: 'quick', minBet: 10, maxBet: 2000, rtp: .96, sortOrder: 18),
  GameInfo(id: 'war', type: GameType.war, name: 'Card War', tag: 'Table', group: 'table', minBet: 10, maxBet: 2000, rtp: .96, sortOrder: 19),
  GameInfo(id: 'tower', type: GameType.tower, name: 'Tower', tag: 'Climb', group: 'adventure', minBet: 10, maxBet: 2000, rtp: .96, sortOrder: 20),
  GameInfo(id: 'chicken', type: GameType.chicken, name: 'Chicken Road', tag: 'Climb', group: 'adventure', minBet: 10, maxBet: 2000, rtp: .96, sortOrder: 21),
  GameInfo(id: 'pump', type: GameType.pump, name: 'Pump', tag: 'Climb', group: 'adventure', minBet: 10, maxBet: 2000, rtp: .96, sortOrder: 22),
  GameInfo(id: 'moles', type: GameType.moles, name: 'Moles', tag: 'Climb', group: 'adventure', minBet: 10, maxBet: 2000, rtp: .96, sortOrder: 23),
];

class CatalogCubit extends Cubit<CatalogState> {
  CatalogCubit(this._api, {bool Function()? signedIn})
      : _signedIn = signedIn,
        super(const CatalogState());

  final ApiClient _api;

  /// Visitors can browse before they sign in; only a signed in player gets the slot config prefetched.
  final bool Function()? _signedIn;
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

  /// A player just signed in: fetch what games need, even though the list was loaded as a visitor.
  void signedInNow() {
    _warmed = false;
    unawaited(refresh());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _warmed = false;
    ApiSlotsServer.clearCache();
    RoundsHub.clear();
    ApiCache.clear(); // drafts and saved pages belong to the player who just left
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
        final st = await _api.getOpen('/v1/status', timeout: const Duration(seconds: 5));
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
            groups: state.groups,
            popular: state.popular,
            status: ServerStatus.online,
            maintenance: (note['message'] ?? 'Back shortly.').toString(),
            maintenanceScope: (note['scope'] ?? 'all').toString(),
          ));
        }
        return;
      }
      final json = await _api.getOpen('/v1/games', timeout: const Duration(seconds: 6));
      final remote = [
        for (final g in (json['games'] is List ? json['games'] as List : const [])) GameInfo.fromJson(parseMap(g)),
      ];
      final byId = {for (final g in defaultGames) g.id: g};
      for (final g in remote) {
        byId[g.id] = g;
      }
      final merged = byId.values.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      _fails = 0;
      final groups = [
        for (final g in (json['groups'] is List ? json['groups'] as List : const []))
          GameGroupInfo(parseString(parseMap(g)['id']) ?? '', parseString(parseMap(g)['name']) ?? ''),
      ];
      final popular = [for (final p in (json['popular'] is List ? json['popular'] as List : const [])) p.toString()];
      final m = json['maintenance'];
      final pause = m is Map ? parseMap(m) : null;
      if (!isClosed) {
        emit(CatalogState(
          games: merged,
          groups: groups,
          popular: popular,
          status: ServerStatus.online,
          maintenance: pause == null ? null : (pause['message'] ?? 'Back shortly.').toString(),
          maintenanceScope: (pause?['scope'] ?? 'all').toString(),
        ));
      }
      if (!_warmed && (_signedIn?.call() ?? true)) {
        // The server is up: fetch what the first game needs now, while the lobby is on screen.
        _warmed = true;
        unawaited(ApiSlotsServer.prefetch(_api));
      }
    } on ApiException catch (e) {
      _fails++;
      if (isClosed) return;
      // A 401 means the sign in is changing; don't flash a scary warning for it.
      if (e.status == 401) {
        emit(CatalogState(games: state.games, groups: state.groups, popular: state.popular, status: state.status, maintenance: state.maintenance, maintenanceScope: state.maintenanceScope));
      } else {
        emit(CatalogState(games: state.games, groups: state.groups, popular: state.popular, status: ServerStatus.offline, message: _explain(e), noConnection: e.isOffline, slow: e.isSlow, unreachable: e.code == 'unreachable'));
      }
    } catch (_) {
      _fails++;
      if (!isClosed) emit(CatalogState(games: state.games, groups: state.groups, popular: state.popular, status: ServerStatus.offline, message: _explain(null), noConnection: false));
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
    if (e.isSlow) return 'Your connection is slow. Please try again.';
    if (e.code == 'unreachable') return "We couldn't reach our servers. Please try again.";
    return "We're experiencing downtime. We're working to get things back.";
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
