import 'model_json.dart';

/// The games. The `name` is what is stored in Firestore and the cache.
enum GameType {
  slots,
  roulette,
  blackjack,
  dice,
  crash,
  plinko;

  /// Unknown names fall back to slots so an old app never crashes on a new game id.
  static GameType fromName(Object? name) => enumByName(GameType.values, name, GameType.slots);
}
