import 'package:flutter/painting.dart';

enum SlotSymbol { seven, bar, bell, cherry, diamond, clover, star }

const symbolNames = {
  SlotSymbol.seven: 'Seven',
  SlotSymbol.bar: 'Bar',
  SlotSymbol.bell: 'Bell',
  SlotSymbol.cherry: 'Cherry',
  SlotSymbol.diamond: 'Diamond',
  SlotSymbol.clover: 'Clover',
  SlotSymbol.star: 'Star',
};

/// How one slot machine looks: the words on its sign, the symbols on its reels and what the reels show
/// before the first spin. The pay table itself always comes from the server.
class SlotTheme {
  const SlotTheme({
    required this.id,
    required this.first,
    required this.second,
    required this.firstColor,
    required this.firstGlow,
    required this.secondColor,
    required this.secondGlow,
    required this.symbols,
    required this.initial,
  });

  final String id;
  final String first, second;
  final Color firstColor, firstGlow, secondColor, secondGlow;
  final List<SlotSymbol> symbols;

  /// Three reels, each [top, payline, bottom].
  final List<List<SlotSymbol>> initial;

  String get name => '$first $second';
  List<SlotSymbol> get startLine => [for (final c in initial) c[1]];
}

const Map<String, SlotTheme> slotThemes = {
  'slots': SlotTheme(
    id: 'slots',
    first: 'Golden',
    second: 'Reels',
    firstColor: Color(0xFFFFD36B),
    firstGlow: Color(0xFFFFC83D),
    secondColor: Color(0xFFE6BBFF),
    secondGlow: Color(0xFFB26BFF),
    symbols: [SlotSymbol.seven, SlotSymbol.bar, SlotSymbol.bell, SlotSymbol.cherry, SlotSymbol.diamond],
    initial: [
      [SlotSymbol.diamond, SlotSymbol.seven, SlotSymbol.bar],
      [SlotSymbol.bell, SlotSymbol.bar, SlotSymbol.cherry],
      [SlotSymbol.cherry, SlotSymbol.bell, SlotSymbol.diamond],
    ],
  ),
  'lucky7': SlotTheme(
    id: 'lucky7',
    first: 'Lucky',
    second: 'Sevens',
    firstColor: Color(0xFFFF9AA3),
    firstGlow: Color(0xFFD62839),
    secondColor: Color(0xFFFFD36B),
    secondGlow: Color(0xFFFFC83D),
    symbols: [SlotSymbol.seven, SlotSymbol.clover, SlotSymbol.star, SlotSymbol.bell, SlotSymbol.bar],
    initial: [
      [SlotSymbol.bar, SlotSymbol.seven, SlotSymbol.star],
      [SlotSymbol.bell, SlotSymbol.clover, SlotSymbol.seven],
      [SlotSymbol.star, SlotSymbol.bar, SlotSymbol.clover],
    ],
  ),
};

SlotTheme slotThemeFor(String? id) => slotThemes[id] ?? slotThemes['slots']!;

class PayRow {
  const PayRow(this.symbols, this.label, this.multiplier, this.probability);
  final List<SlotSymbol> symbols; // icons shown in the paytable
  final String label;
  final int multiplier;
  final double probability; // chance of this outcome per spin (server-side only)
}

class SlotsConfig {
  const SlotsConfig({
    required this.minBet,
    required this.maxBet,
    required this.betSteps,
    required this.defaultBet,
    required this.startBalance,
    required this.bigWinMultiplier,
    required this.rtp,
    required this.payRows,
    this.pairSymbol,
  });
  /// The symbol that pays on any two, when the machine has such a row.
  final SlotSymbol? pairSymbol;
  final double minBet, maxBet, defaultBet, startBalance, rtp;
  final List<double> betSteps;
  final int bigWinMultiplier;
  final List<PayRow> payRows;
  double get maxWin => maxBet * payRows.first.multiplier;
}

class SpinResult {
  const SpinResult({
    required this.columns,
    required this.multiplier,
    required this.payout,
    required this.balanceAfterBet,
    required this.balanceAfter,
    required this.label,
    this.roundId = '',
  });
  final String roundId;
  final List<List<SlotSymbol>> columns; // 3 reels x [top, payline, bottom]
  final int multiplier;
  final double payout;
  final double balanceAfterBet;
  final double balanceAfter;
  final String label;
  bool get isWin => multiplier > 0;
}
