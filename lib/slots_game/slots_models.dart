enum SlotSymbol { seven, bar, bell, cherry, diamond }

const symbolNames = {
  SlotSymbol.seven: 'Seven',
  SlotSymbol.bar: 'Bar',
  SlotSymbol.bell: 'Bell',
  SlotSymbol.cherry: 'Cherry',
  SlotSymbol.diamond: 'Diamond',
};

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
  });
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
  });
  final List<List<SlotSymbol>> columns; // 3 reels x [top, payline, bottom]
  final int multiplier;
  final double payout;
  final double balanceAfterBet;
  final double balanceAfter;
  final String label;
  bool get isWin => multiplier > 0;
}
