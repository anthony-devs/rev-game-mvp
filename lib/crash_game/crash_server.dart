import 'dart:async';
import 'dart:math';

// The crash point is decided on the game server. The page never sees it in
// advance: it only receives ticks, a cash-out confirmation and a crash event.

enum RoundEventType { tick, cashedOut, crashed }

/// Where the crash page is in a round.
enum RoundPhase { betting, running, crashed }

class RoundEvent {
  const RoundEvent._(this.type, this.multiplier, this.balance, this.payout);

  factory RoundEvent.tick(double multiplier, double balance) =>
      RoundEvent._(RoundEventType.tick, multiplier, balance, 0);

  factory RoundEvent.cashedOut(
          double multiplier, double payout, double balance) =>
      RoundEvent._(RoundEventType.cashedOut, multiplier, balance, payout);

  factory RoundEvent.crashed(double crashPoint, double balance) =>
      RoundEvent._(RoundEventType.crashed, crashPoint, balance, 0);

  final RoundEventType type;
  final double multiplier;
  final double balance;
  final double payout;
}

/// What the Crash page needs from the game server (see ApiCrashServer).
abstract class CrashServer {
  /// Credits the player has right now. The page reads it after each event.
  double get balance;
  set balance(double value);

  /// Takes the bet and streams ticks, then `cashedOut` and/or `crashed`.
  /// Errors on the stream mean the bet was not taken.
  Stream<RoundEvent> startRound({required double bet, double? autoCashout});

  /// Asks to cash out now. The answer arrives as a `cashedOut` event.
  void cashOut();

  /// Id of the current or last round, for the Verify screen. `null` before the first.
  String? get roundId;

  void dispose();
}
