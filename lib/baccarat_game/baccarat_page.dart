import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../core/api/api_client.dart';
import '../games/game_support.dart';
import '../model/model.dart';
import '../pages/how_to_play_page.dart';
import '../rounds/rounds_sheet.dart';
import 'baccarat_api.dart';

/// Baccarat (punto banco). The whole hand is dealt on the server.
class BaccaratPage extends StatefulWidget {
  const BaccaratPage({super.key, this.info});

  final GameInfo? info;

  @override
  State<BaccaratPage> createState() => _BaccaratPageState();
}

class _BaccaratPageState extends State<BaccaratPage> with GameSessionMixin<BaccaratPage> {
  @override
  GameType get guideType => GameType.baccarat;

  static const _chips = <double>[10, 50, 100, 500, 1000];
  static const _sides = <String>['player', 'tie', 'banker'];

  late final BaccaratApi _api;

  double _chip = 100;
  final Map<String, double> _bets = {};
  BaccaratResult? _result;
  bool _busy = false;

  double get _minBet => widget.info?.minBet ?? 10;
  double get _maxTotal => maxBetFor(widget.info?.maxBet ?? 5000);
  double get _total => _bets.values.fold(0.0, (a, b) => a + b);

  @override
  void initState() {
    super.initState();
    _api = BaccaratApi(context.read<ApiClient>());
    _chip = _chip.clamp(_minBet, _maxTotal).toDouble();
  }

  Future<void> _release(double expected) async {
    for (var i = 0; i < 30; i++) {
      if (!mounted) return;
      if ((walletBalance - expected).abs() < .005) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (mounted && !_busy) releaseBalance();
  }

  void _place(String side) {
    if (_busy) return;
    if (_result != null) setState(() => _result = null);
    if (_total + _chip > _maxTotal) {
      showToast(context, 'Total bet can be at most ${formatCredits(_maxTotal, decimals: 0)}.');
      return;
    }
    if (_total + _chip > walletBalance) {
      showNoCredits(context, needed: _total + _chip);
      return;
    }
    AppSound.play(Sfx.chip);
    AppHaptics.selection();
    setState(() => _bets[side] = (_bets[side] ?? 0) + _chip);
  }

  void _clear() {
    if (_busy) return;
    AppSound.play(Sfx.tap);
    setState(() {
      _bets.clear();
      _result = null;
    });
  }

  Future<void> _deal() async {
    if (_busy) return;
    if (_bets.isEmpty) {
      showToast(context, 'Place a bet first.');
      return;
    }
    if (!checkCanPlay()) return;
    final total = _total;
    if (total > walletBalance) {
      showNoCredits(context, needed: total);
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
    });
    holdBalance(walletBalance - total);
    AppSound.play(Sfx.card);
    AppHaptics.light();
    try {
      final r = await _api.play(Map<String, double>.from(_bets));
      if (!mounted) return;
      setState(() {
        _result = r;
        _busy = false;
      });
      holdBalance(r.balance);
      reportRound(bet: r.bet, payout: r.payout);
      if (r.isWin) {
        AppSound.play(r.payout >= r.bet * 5 ? Sfx.bigWin : Sfx.win);
        AppHaptics.medium();
      } else if (r.isPush) {
        AppSound.play(Sfx.cardFlip);
      } else {
        AppSound.play(Sfx.lose);
      }
      _release(r.balance);
    } catch (e) {
      releaseBalance();
      AppSound.play(Sfx.error);
      if (!mounted) return;
      setState(() => _busy = false);
      if (failKind(e) == FailKind.noRounds) {
        showRoundsSheet(context);
      } else if (failKind(e) == FailKind.noCredits) {
        showNoCredits(context, needed: total);
      } else {
        showToast(context, failText(e), error: true);
      }
    }
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final balance = watchBalance(context);
    final r = _result;
    final tone = r == null ? AppColors.purple : (r.isWin ? AppColors.green : (r.isPush ? AppColors.gold : AppColors.loss));

    return GameScaffold(
      title: 'Baccarat',
      balance: balance,
      lowBalance: walletBalance < _minBet && !_busy,
      glowColor: tone,
      onHelp: () => openGuide(context, GameType.baccarat),
      onVerify: () => openFairness(context, roundId: r?.roundId),
      banner: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: AppColors.surfaceAlt,
        alignment: Alignment.center,
        child: Text('PLAYER 1:1  ·  BANKER 0.95:1  ·  TIE 8:1', style: AppText.label(color: AppColors.gold, size: 10)),
      ),
      stage: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _hand('BANKER', 'banker', r?.banker ?? const [], r?.bankerTotal, r),
            const SizedBox(height: 18),
            _middle(r),
            const SizedBox(height: 18),
            _hand('PLAYER', 'player', r?.player ?? const [], r?.playerTotal, r),
          ]),
        ),
      ),
      panel: _panel(r, tone),
    );
  }

  Widget _middle(BaccaratResult? r) {
    final text = _busy
        ? 'Dealing...'
        : r == null
            ? 'Place your bets'
            : (r.winner == 'tie' ? 'TIE' : '${r.winner.toUpperCase()} WINS') + (r.natural ? '  ·  NATURAL' : '');
    final color = r == null ? AppColors.textMuted : (r.winner == 'tie' ? AppColors.gold : AppColors.text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.line)),
      child: Text(text, style: AppText.label(color: color, size: 11)),
    );
  }

  Widget _hand(String title, String side, List<String> cards, int? total, BaccaratResult? r) {
    final won = r != null && r.winner == side;
    final tie = r != null && r.winner == 'tie';
    final edge = won ? AppColors.green : (tie ? AppColors.gold : Colors.transparent);
    // Deal order is player, banker, player, banker, then the third cards.
    int order(int i) => side == 'player' ? i * 2 : i * 2 + 1;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: edge, width: 1.6)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: AppText.label()),
          if (total != null && cards.isNotEmpty) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(color: won ? AppColors.green : AppColors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
              child: Text('$total', style: AppText.number(13, color: won ? Colors.white : AppColors.text)),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 98,
          child: cards.isEmpty
              ? Center(child: Text(_busy ? '' : '--', style: AppText.body(12, color: AppColors.textFaint)))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 0; i < cards.length; i++)
                    Padding(
                      key: ValueKey('${r?.roundId}_${side}_$i'),
                      padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                      child: _Dealt(order: order(i), child: _face(cards[i], 58)),
                    ),
                ]),
        ),
      ]),
    );
  }

  Widget _face(String c, double width) {
    final rank = c.substring(0, c.length - 1);
    final suit = switch (c[c.length - 1]) {
      'S' => CardSuit.spades,
      'H' => CardSuit.hearts,
      'D' => CardSuit.diamonds,
      _ => CardSuit.clubs,
    };
    return PlayingCardView(rank: rank, suit: suit, width: width);
  }

  Widget _zone(String side) {
    final amount = _bets[side] ?? 0;
    final (name, pays, color) = switch (side) {
      'player' => ('PLAYER', '1:1', AppColors.blue),
      'banker' => ('BANKER', '0.95:1', AppColors.loss),
      _ => ('TIE', '8:1', AppColors.green),
    };
    final lit = amount > 0;
    final won = _result != null && _result!.winner == side;
    return Expanded(
      child: PressScale(
        onTap: _busy ? null : () => _place(side),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: lit ? color.withValues(alpha: .14) : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: won ? AppColors.green : (lit ? color : AppColors.line), width: lit || won ? 1.6 : 1),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(name, style: AppText.label(color: color, size: 11)),
            const SizedBox(height: 2),
            Text(pays, style: AppText.body(10, color: AppColors.textMuted)),
            const SizedBox(height: 6),
            SizedBox(
              height: 20,
              child: FittedBox(fit: BoxFit.scaleDown, child: Text(lit ? formatCredits(amount, decimals: 0) : '+', style: AppText.number(15, color: lit ? AppColors.gold : AppColors.textFaint))),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _panel(BaccaratResult? r, Color tone) {
    final children = <Widget>[
      if (r != null) ...[
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.isWin ? 'YOU WON' : (r.isPush ? 'BET RETURNED' : 'NO WIN'), style: AppText.label(color: tone)),
              const SizedBox(height: 2),
              Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(12, color: AppColors.textMuted)),
            ]),
          ),
          Text(formatSigned(r.net), style: AppText.number(26, color: tone, shadows: r.isWin ? AppText.glow(tone, opacity: .4) : null)),
        ]),
        const SizedBox(height: 12),
      ],
      Row(children: [for (var i = 0; i < _sides.length; i++) ...[if (i > 0) const SizedBox(width: 8), _zone(_sides[i])]]),
      const SizedBox(height: 12),
      BetChipPicker(values: _chips, selected: _chip, size: 50, onSelected: (v) {
        AppSound.play(Sfx.chip);
        setState(() => _chip = v.clamp(_minBet, _maxTotal).toDouble());
      }),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: AppButton(label: 'Clear', variant: AppButtonVariant.outline, height: 56, fontSize: 15, onPressed: _busy || _bets.isEmpty ? null : _clear)),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: AppButton(label: r == null ? 'DEAL' : 'DEAL AGAIN', sublabel: _bets.isEmpty ? null : 'BET ${formatCredits(_total, decimals: 0)}', variant: AppButtonVariant.success, height: 56, fontSize: 16, loading: _busy, onPressed: _busy || _bets.isEmpty ? null : _deal)),
      ]),
      if (r != null)
        PressScale(
          onTap: () => openFairness(context, roundId: r.roundId),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Verify this round', style: AppText.body(13, weight: FontWeight.w600, color: AppColors.green, decoration: TextDecoration.underline)),
          ),
        ),
    ];
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppColors.sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: AnimatedSize(duration: const Duration(milliseconds: 180), alignment: Alignment.topCenter, child: Column(mainAxisSize: MainAxisSize.min, children: children)),
    );
  }
}

/// A card slides in from above and settles with a small bounce.
class _Dealt extends StatelessWidget {
  const _Dealt({required this.child, this.order = 0});

  final Widget child;
  final int order;

  @override
  Widget build(BuildContext context) {
    final lead = (order * 110).clamp(0, 550);
    final total = 280 + lead;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(lead / total, 1, curve: Curves.easeOutBack),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, -34 * (1 - t)), child: Transform.scale(scale: .86 + .14 * t, child: child)),
      ),
      child: child,
    );
  }
}
