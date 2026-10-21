import 'slots_models.dart';

/// What the Slots page needs from the game server. [ApiSlotsServer] is the real one.
abstract class SlotsServer {
  Future<SlotsConfig> fetchConfig();
  String get game;
  Future<SpinResult> spin(double bet);
}
