import 'dart:async';
import 'dart:math';

// --------------------------------------------------------------------------- "Server" side ---------------------------------------------------------------------------
//
// Everything that decides the outcome lives here. The page never sees the
// crash point in advance: it only receives ticks, a cash-out confirmation and
// a crash event. To go live, implement the same three things (startRound
// stream, cashOut, balance) against your Edge Function / realtime channel and
// delete this class. The page code does not change.

enum RoundEventType { tick, cashedOut, crashed }

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

class MockCrashServer {
  MockCrashServer({
    this.balance = 100000.0,
    this.houseEdge = 0.03,
    this.growthRate = 0.12,
    this.maxCrash = 5000.0,
  });

  /// Virtual credits only.
  double balance;
  final double houseEdge;
  final double growthRate;
  final double maxCrash;

  final Random _rng = Random();
  final Stopwatch _clock = Stopwatch();
  StreamController<RoundEvent>? _ctrl;
  Timer? _timer;
  double _crashPoint = 1.0;
  double _bet = 0;
  double? _autoCashout;
  bool _cashedOut = false;

  double _multiplierNow() =>
      exp(growthRate * (_clock.elapsedMicroseconds / 1000000));

  double _drawCrashPoint() {
    final r = _rng.nextDouble();
    final raw = (100 * (1 - houseEdge) / (1 - r)).floorToDouble() / 100;
    return raw.clamp(1.0, maxCrash).toDouble();
  }

  Stream<RoundEvent> startRound({required double bet, double? autoCashout}) {
    _timer?.cancel();
    _ctrl?.close();

    balance -= bet;
    _bet = bet;
    _autoCashout =
        autoCashout == null ? null : (autoCashout * 100).round() / 100;
    _cashedOut = false;
    _crashPoint = _drawCrashPoint();

    final ctrl = StreamController<RoundEvent>();
    _ctrl = ctrl;
    _clock
      ..reset()
      ..start();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
    return ctrl.stream;
  }

  void _tick() {
    final ctrl = _ctrl;
    if (ctrl == null || ctrl.isClosed) return;

    final m = _multiplierNow();

    if (m >= _crashPoint) {
      _timer?.cancel();
      ctrl.add(RoundEvent.crashed(_crashPoint, balance));
      ctrl.close();
      _ctrl = null;
      return;
    }

    final auto = _autoCashout;
    if (!_cashedOut && auto != null && m >= auto) {
      _settleCashout(auto);
    }
    ctrl.add(RoundEvent.tick(m, balance));
  }

  void _settleCashout(double at) {
    _cashedOut = true;
    final payout = _bet * at;
    balance += payout;
    _ctrl?.add(RoundEvent.cashedOut(at, payout, balance));
  }

  /// The server clock is the truth: too late means the round already crashed.
  bool cashOut() {
    if (_ctrl == null || _cashedOut) return false;
    final m = _multiplierNow();
    if (m >= _crashPoint) return false;
    _settleCashout((m * 100).floorToDouble() / 100);
    return true;
  }

  void dispose() {
    _timer?.cancel();
    _ctrl?.close();
  }
}

/// Where the round is. Shared by the page and the widgets.
enum RoundPhase { betting, running, crashed }
