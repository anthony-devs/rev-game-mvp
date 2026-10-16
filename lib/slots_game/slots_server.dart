import 'dart:math' as math;

import 'slots_models.dart';

abstract class SlotsServer {
  Future<SlotsConfig> fetchConfig();
  Future<SpinResult> spin(double bet);
  Future<double> topUp();
}

/// Stand-in for your backend. Outcomes are drawn from the outcome table below
/// (probabilities sum to RTP 0.96), then reels are built to match the outcome.
class MockSlotsServer implements SlotsServer {
  MockSlotsServer();
  final _rnd = math.Random();
  double _balance = 10000;

  static const _rows = [
    PayRow([SlotSymbol.seven, SlotSymbol.seven, SlotSymbol.seven], 'Seven', 100, 0.0004),
    PayRow([SlotSymbol.diamond, SlotSymbol.diamond, SlotSymbol.diamond], 'Diamond', 50, 0.001),
    PayRow([SlotSymbol.bell, SlotSymbol.bell, SlotSymbol.bell], 'Bell', 25, 0.004),
    PayRow([SlotSymbol.bar, SlotSymbol.bar, SlotSymbol.bar], 'Bar', 15, 0.008),
    PayRow([SlotSymbol.cherry, SlotSymbol.cherry, SlotSymbol.cherry], 'Cherry', 10, 0.012),
    PayRow([SlotSymbol.cherry, SlotSymbol.cherry], 'Any 2 cherries', 2, 0.265),
  ];
  // RTP = 0.0004*100 + 0.001*50 + 0.004*25 + 0.008*15 + 0.012*10 + 0.265*2 = 0.96

  @override
  Future<SlotsConfig> fetchConfig() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return const SlotsConfig(
      minBet: 10,
      maxBet: 1000,
      betSteps: [10, 20, 50, 100, 200, 500, 1000],
      defaultBet: 100,
      startBalance: 10000,
      bigWinMultiplier: 50,
      rtp: 0.96,
      payRows: _rows,
    );
  }

  @override
  Future<double> topUp() async {
    _balance = 10000;
    return _balance;
  }

  SlotSymbol _any() => SlotSymbol.values[_rnd.nextInt(SlotSymbol.values.length)];

  List<SlotSymbol> _losingLine() {
    while (true) {
      final l = [_any(), _any(), _any()];
      final cherries = l.where((s) => s == SlotSymbol.cherry).length;
      final triple = l[0] == l[1] && l[1] == l[2];
      if (!triple && cherries != 2) return l;
    }
  }

  List<SlotSymbol> _twoCherries() {
    final other = SlotSymbol.values.where((s) => s != SlotSymbol.cherry).toList();
    final l = [SlotSymbol.cherry, SlotSymbol.cherry, other[_rnd.nextInt(other.length)]]..shuffle(_rnd);
    return l;
  }

  @override
  Future<SpinResult> spin(double bet) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (bet > _balance) throw StateError('insufficient_credits');
    _balance -= bet;
    final afterBet = _balance;

    final r = _rnd.nextDouble();
    var acc = 0.0;
    PayRow? hit;
    for (final row in _rows) {
      acc += row.probability;
      if (r < acc) {
        hit = row;
        break;
      }
    }

    late final List<SlotSymbol> line;
    String label = 'No win';
    if (hit == null) {
      line = _losingLine();
    } else if (hit.symbols.length == 3) {
      line = List.filled(3, hit.symbols.first);
      label = '3x ${hit.label} - pays x${hit.multiplier}';
    } else {
      line = _twoCherries();
      label = '2x Cherry - pays x${hit.multiplier}';
    }

    final mult = hit?.multiplier ?? 0;
    final payout = bet * mult;
    _balance += payout;

    final columns = [
      for (var i = 0; i < 3; i++) [_any(), line[i], _any()],
    ];
    return SpinResult(
      columns: columns,
      multiplier: mult,
      payout: payout,
      balanceAfterBet: afterBet,
      balanceAfter: _balance,
      label: label,
    );
  }
}
