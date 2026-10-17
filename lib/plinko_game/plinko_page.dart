import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show TickerCanceled;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../core/api/api_client.dart';
import '../games/game_support.dart';
import '../rounds/rounds_sheet.dart';
import '../model/model.dart';
import '../pages/how_to_play_page.dart';
import '../user/bloc/profile_cubit.dart';
import '../user/data/user_repository.dart';
import 'plinko_api.dart';
import 'plinko_board.dart';

/// Plinko: choose a risk level and the number of rows, drop the ball. The server decides the
/// path (provably fair); the screen only plays it back.
class PlinkoPage extends StatefulWidget {
  const PlinkoPage({super.key, this.info});

  final GameInfo? info;

  @override
  State<PlinkoPage> createState() => _PlinkoPageState();
}

class _PlinkoPageState extends State<PlinkoPage> with GameSessionMixin<PlinkoPage>, SingleTickerProviderStateMixin {
  @override
  GameType get guideType => GameType.plinko;

  late final PlinkoApi _api;
  late final AnimationController _anim;

  int _rows = 12;
  PlinkoRisk _risk = PlinkoRisk.medium;
  PlinkoQuote? _quote;
  bool _quoteFailed = false;
  int _quoteToken = 0;

  double _bet = 100;
  double _lastBet = 100;
  bool _dropping = false;
  PlinkoResult? _res;
  bool _landed = false;
  final List<({double multiplier, bool win})> _history = [];

  double get _minBet => _quote?.minBet ?? widget.info?.minBet ?? 10;
  double get _boardMax => _quote?.maxBet ?? widget.info?.maxBet ?? 100000;
  double get _maxBet => maxBetFor(_boardMax);

  @override
  void initState() {
    super.initState();
    _api = PlinkoApi(context.read<ApiClient>());
    _anim = AnimationController(vsync: this)..addListener(() => setState(() {}));
    _bet = _bet.clamp(_minBet, _maxBet).toDouble();
    PlayMode.live.addListener(_loadQuote); // demo and live boards pay differently
    scheduleMicrotask(_loadQuote);
    _loadHistory();
  }

  @override
  void dispose() {
    PlayMode.live.removeListener(_loadQuote);
    _anim.dispose();
    super.dispose();
  }

  Future<void> _loadQuote() async {
    final token = ++_quoteToken;
    setState(() {
      _quoteFailed = false;
    });
    try {
      final q = await _api.quote(_rows, _risk);
      if (!mounted || token != _quoteToken) return;
      setState(() {
        _quote = q;
        _bet = _bet.clamp(_minBet, _maxBet).toDouble();
      });
    } catch (_) {
      if (!mounted || token != _quoteToken) return;
      setState(() => _quoteFailed = true);
    }
  }

  Future<void> _loadHistory() async {
    try {
      final rounds = await context
          .read<UserRepository>()
          .watchRounds(profile.state.dataId, game: GameType.plinko, limit: 12)
          .first
          .timeout(const Duration(seconds: 4));
      if (!mounted || _history.isNotEmpty) return;
      setState(() {
        for (final r in rounds) {
          _history.add((multiplier: r.multiplier, win: r.isWin));
        }
      });
    } catch (_) {}
  }

  void _setBet(double v) => setState(() => _bet = v.clamp(_minBet, _maxBet).toDouble());

  void _setBoard({int? rows, PlinkoRisk? risk}) {
    if (_dropping) return;
    AppHaptics.selection();
    setState(() {
      _rows = rows ?? _rows;
      _risk = risk ?? _risk;
      _res = null;
      _landed = false;
      _quote = null;
      _anim.value = 0;
    });
    _loadQuote();
  }

  Future<void> _drop() async {
    if (_dropping) return;
    final quote = _quote;
    if (quote == null) {
      if (_quoteFailed) _loadQuote();
      return;
    }
    if (!checkCanPlay()) return;
    if (_bet > walletBalance) {
      showNoCredits(context, needed: _bet);
      return;
    }
    setState(() {
      _dropping = true;
      _res = null;
      _landed = false;
      _lastBet = _bet;
      _anim.value = 0;
    });
    holdBalance(walletBalance - _bet);
    AppSound.play(Sfx.ballDrop);
    AppHaptics.light();

    final PlinkoResult res;
    try {
      res = await _api.drop(bet: _bet, rows: _rows, risk: _risk);
    } catch (e) {
      releaseBalance();
      AppSound.play(Sfx.error);
      if (!mounted) return;
      setState(() => _dropping = false);
      if (failKind(e) == FailKind.noRounds) {
      showRoundsSheet(context);
    } else if (failKind(e) == FailKind.noCredits) {
        showNoCredits(context, needed: _bet);
      } else {
        showToast(context, failText(e), error: true);
      }
      _loadQuote(); // the board or limits may have changed
      return;
    }
    if (!mounted) return;
    setState(() => _res = res);

    // Play the path the server chose.
    _anim.duration = Duration(milliseconds: 260 + res.rows * 190);
    try {
      await _anim.forward(from: 0).orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted) return;

    setState(() {
      _landed = true;
      _dropping = false;
      _history.insert(0, (multiplier: res.multiplier, win: res.win));
      if (_history.length > 12) _history.removeLast();
    });
    holdBalance(res.balance);
    reportRound(bet: _lastBet, payout: res.payout);
    if (res.payout > _lastBet) {
      AppHaptics.medium();
      AppSound.play(res.multiplier >= 10 ? Sfx.bigWin : Sfx.win);
    } else {
      AppSound.play(Sfx.lose);
    }
    unawaited(_settle(res.balance));
  }

  Future<void> _settle(double expected) async {
    for (var i = 0; i < 30; i++) {
      if (!mounted) return;
      if ((walletBalance - expected).abs() < .005) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (mounted && !_dropping) releaseBalance();
  }

  @override
  Widget build(BuildContext context) {
    final res = _res;
    final quote = _quote;
    final balance = watchBalance(context);
    final shown = _landed ? res : null;
    final tone = shown == null ? AppColors.text : (shown.payout > _lastBet ? AppColors.green : AppColors.loss);

    return GameScaffold(
      title: 'Plinko',
      balance: balance,
      lowBalance: walletBalance < _minBet && !_dropping,
      glowColor: shown == null ? AppColors.mint : tone,
      onHelp: () => openGuide(context, GameType.plinko),
      onVerify: () => openFairness(context, roundId: res?.roundId),
      stage: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        children: [
          SizedBox(
            height: 34,
            child: _history.isEmpty
                ? Align(alignment: Alignment.centerLeft, child: Text('Your last drops show here', style: AppText.body(12, color: AppColors.textFaint)))
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _history.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final h = _history[i];
                      final c = h.win ? AppColors.green : AppColors.loss;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(20), border: Border.all(color: c.withValues(alpha: .5))),
                        child: Text('${_fmt(h.multiplier)}×', style: AppText.number(12, color: c, weight: FontWeight.w700)),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 10),
          Center(
            child: SizedBox(
              height: 34,
              child: shown == null
                  ? null
                  : StatusPill(label: shown.payout > _lastBet ? 'WIN · ${_fmt(shown.multiplier)}×' : '${_fmt(shown.multiplier)}×', color: tone),
            ),
          ),
          const SizedBox(height: 6),
          PlinkoBoard(
            rows: _rows,
            multipliers: quote?.multipliers ?? const [],
            path: res?.path ?? const [],
            progress: _anim.value,
            landedSlot: _landed ? res?.slot : null,
            loading: quote == null,
          ),
          if (_quoteFailed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Center(
                child: TextButton(onPressed: _loadQuote, child: Text("Couldn't load the board. Tap to retry", style: AppText.body(13, weight: FontWeight.w700, color: AppColors.loss))),
              ),
            ),
          const SizedBox(height: 14),
          IgnorePointer(
            ignoring: _dropping,
            child: SegmentedToggle<PlinkoRisk>(
              options: [for (final r in PlinkoRisk.values) SegmentOption(value: r, label: r.label)],
              selected: _risk,
              onChanged: (v) => _setBoard(risk: v),
            ),
          ),
          const SizedBox(height: 10),
          IgnorePointer(
            ignoring: _dropping,
            child: SegmentedToggle<int>(
              options: [for (final r in plinkoRows) SegmentOption(value: r, label: '$r rows')],
              selected: _rows,
              height: 44,
              onChanged: (v) => _setBoard(rows: v),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: StatTile(label: 'Top win', value: quote == null ? '--' : '${_fmt(quote.top)}×')),
              const SizedBox(width: 10),
              Expanded(
                child: quote == null
                    ? const StatTile(label: 'Return', value: '--')
                    : (quote.rtp <= 1
                        ? StatTile(label: 'Return', value: '${(quote.rtp * 100).toStringAsFixed(1)}%')
                        : StatTile(label: 'Lowest', value: '${_fmt(quote.multipliers.reduce((a, b) => a < b ? a : b))}×')),
              ),
              const SizedBox(width: 10),
              Expanded(child: StatTile(label: 'Max bet', value: quote == null ? '--' : formatCredits(_maxBet, decimals: 0))),
            ],
          ),
        ],
      ),
      panel: BetPanel(
        bet: _bet,
        minBet: _minBet,
        maxBet: _maxBet,
        onBetChanged: _setBet,
        busy: _dropping,
        actionLabel: res == null ? 'DROP' : 'DROP AGAIN',
        onAction: (_dropping || quote == null) ? null : _drop,
        extra: shown != null
            ? Column(
                children: [
                  WinBanner(
                    amount: shown.payout - _lastBet,
                    lossLabel: shown.payout > _lastBet ? 'WIN' : 'ROUND LOST',
                    caption: 'Landed on ${_fmt(shown.multiplier)}×',
                  ),
                  const SizedBox(height: 6),
                  PressScale(
                    onTap: () => openFairness(context, roundId: shown.roundId),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text('Verify this round', style: AppText.body(13, weight: FontWeight.w600, color: AppColors.green, decoration: TextDecoration.underline)),
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Highest possible win', style: AppText.body(13, color: AppColors.textDim)),
                  Text(quote == null ? '--' : '+${formatCredits(_bet * quote.top - _bet, decimals: 0)}', style: AppText.number(14, color: AppColors.green)),
                ],
              ),
      ),
    );
  }

  static String _fmt(double m) => m >= 100 ? m.toStringAsFixed(0) : (m >= 10 ? m.toStringAsFixed(1) : m.toStringAsFixed(2));
}
