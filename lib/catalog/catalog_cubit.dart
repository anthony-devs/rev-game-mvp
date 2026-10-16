import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../model/model.dart';
import '../user/data/user_repository.dart';

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

/// What the lobby shows. Built-in list first, then the Firestore `games`
/// collection on top of it, so a game can be paused, renamed or announced
/// without an app update:
///
/// ```
/// games/dice        { enabled: false }          -> "Game unavailable"
/// games/plinko      { name: 'Plinko', tag: 'Instant', comingSoon: true, type: 'dice' }
/// ```
class CatalogState extends Equatable {
  const CatalogState({this.games = defaultGames});

  final List<GameInfo> games;

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
  List<Object?> get props => [games];
}

const List<GameInfo> defaultGames = [
  GameInfo(id: 'slots', type: GameType.slots, name: 'Golden Reels', tag: 'Slots', minBet: 10, maxBet: 1000, rtp: .96, sortOrder: 1),
  GameInfo(id: 'crash', type: GameType.crash, name: 'Dash Crash', tag: 'Instant', minBet: 10, maxBet: 500000, rtp: .97, sortOrder: 2),
  GameInfo(id: 'roulette', type: GameType.roulette, name: 'Euro Roulette', tag: 'Table', minBet: 10, maxBet: 100000, rtp: .973, sortOrder: 3),
  GameInfo(id: 'blackjack', type: GameType.blackjack, name: 'Blackjack', tag: 'Table', minBet: 10, maxBet: 100000, rtp: .99, sortOrder: 4),
  GameInfo(id: 'dice', type: GameType.dice, name: 'Dice', tag: 'Instant', minBet: 10, maxBet: 100000, rtp: .97, sortOrder: 5),
  GameInfo(id: 'soon-lucky7', type: GameType.slots, name: 'Lucky Sevens', tag: 'Slots', comingSoon: true, sortOrder: 20),
  GameInfo(id: 'soon-fruit', type: GameType.slots, name: 'Fruit Frenzy', tag: 'Slots', comingSoon: true, sortOrder: 21),
  GameInfo(id: 'soon-diamond', type: GameType.slots, name: 'Diamond Deluxe', tag: 'Slots', comingSoon: true, sortOrder: 22),
  GameInfo(id: 'soon-mines', type: GameType.dice, name: 'Mines', tag: 'Instant', comingSoon: true, sortOrder: 23),
  GameInfo(id: 'soon-plinko', type: GameType.dice, name: 'Plinko', tag: 'Instant', comingSoon: true, sortOrder: 24),
  GameInfo(id: 'soon-baccarat', type: GameType.blackjack, name: 'Baccarat', tag: 'Table', comingSoon: true, sortOrder: 25),
];

class CatalogCubit extends Cubit<CatalogState> {
  CatalogCubit(this._repo) : super(const CatalogState());

  final UserRepository _repo;
  StreamSubscription<List<GameInfo>>? _sub;

  /// Start listening (call after sign in; the rules need a signed in player).
  void start() {
    _sub?.cancel();
    _sub = _repo.watchGames().listen((remote) {
      final byId = {for (final g in defaultGames) g.id: g};
      for (final g in remote) {
        byId[g.id] = g;
      }
      final merged = byId.values.toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      emit(CatalogState(games: merged));
    }, onError: (_) {/* keep the built-in list */});
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    emit(const CatalogState());
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
