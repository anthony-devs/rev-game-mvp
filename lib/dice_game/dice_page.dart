import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../core/api/api_client.dart';
import '../games/game_support.dart';
import '../rounds/rounds_sheet.dart';
import '../model/model.dart';
import '../user/bloc/profile_cubit.dart';
import '../user/data/user_repository.dart';
import 'dice_api.dart';
import '../pages/how_to_play_page.dart';

/// G4. Dice: pick a target, roll under or over. Decided on the server.
class DicePage extends StatefulWidget {
  const DicePage({super.key, this.info});

  final GameInfo? info;

  @override
  State<DicePage> createState() => _DicePageState();
}

class _DicePageState extends State<DicePage> with GameSessionMixin<DicePage> {
  @override
  GameType get guideType => GameType.dice;

  late final DiceApi _api;
  final _rnd = math.Random();

  double _bet = 100;
  double _lastBet = 100; // the stake of the round on screen
  double _target = 50;
  bool _over = false;

  bool _rolling = false;
  DiceResult? _res;
  double? _display;
  Timer? _cycle;
  final List<DiceResult> _history = [];

  double get _minBet => widget.info?.minBet ?? 10;
  double get _maxBet => maxBetFor(widget.info?.maxBet ?? 100000);
  double get _chance => DiceMath.chance(_target, _over);
  double get _mult => DiceMath.multiplier(_chance);
  double get _profit => _bet * _mult - _bet;

  @override
  void initState() {
    super.initState();
    _api = DiceApi(context.read<ApiClient>());
    _bet = _bet.clamp(_minBet, _maxBet).toDouble();
    _loadHistory();
  }

  @override
  void dispose() {
    _cycle?.cancel();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final rounds = await context
          .read<UserRepository>()
          .watchRounds(profile.state.dataId, game: GameType.dice, limit: 12)
          .first
          .timeout(const Duration(seconds: 4));
      if (!mounted || _history.isNotEmpty) return;
      setState(() {
        for (final r in rounds) {
          final roll = parseRoll(r);
          if (roll != null) _history.add(DiceResult(roundId: r.id, roll: roll, win: r.isWin, target: 0, over: false, multiplier: r.multiplier, chance: 0, payout: r.payout, balanceAfterBet: 0, balance: 0));
        }
      });
    } catch (_) {}
  }

  /// Reads the roll back out of a stored round ("Rolled 52.38, over 50.00").
  static double? parseRoll(GameRound r) {
    final v = r.details['roll'];
    return v is num ? v.toDouble() : null;
  }

  void _setBet(double v) => setState(() => _bet = v.clamp(_minBet, _maxBet).toDouble());

  void _setTarget(double v) {
    if (_rolling) return;
    setState(() => _target = v.clamp(DiceMath.minTarget, DiceMath.maxTarget).roundToDouble());
  }

  Future<void> _roll() async {
    if (_rolling) return;
    if (!checkCanPlay()) return;
    if (_bet > walletBalance) {
      showNoCredits(context, needed: _bet);
      return;
    }
    setState(() {
      _rolling = true;
      _res = null;
      _lastBet = _bet;
    });
    holdBalance(walletBalance - _bet);
    AppSound.play(Sfx.diceRoll);
    AppHaptics.light();
    _cycle = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (mounted) setState(() => _display = DiceMath.randomDisplay(_rnd));
    });

    final started = DateTime.now();
    final DiceResult res;
    try {
      res = await _api.roll(bet: _bet, target: _target, over: _over);
    } catch (e) {
      _cycle?.cancel();
      releaseBalance();
      AppSound.play(Sfx.error);
      if (!mounted) return;
      setState(() {
        _rolling = false;
        _display = null;
      });
      if (failKind(e) == FailKind.noRounds) {
      showRoundsSheet(context);
    } else if (failKind(e) == FailKind.noCredits) {
        showNoCredits(context, needed: _bet);
      } else {
        showToast(context, failText(e), error: true);
      }
      return;
    }
    final elapsed = DateTime.now().difference(started);
    const minRoll = Duration(milliseconds: 750);
    if (elapsed < minRoll) await Future<void>.delayed(minRoll - elapsed);
    _cycle?.cancel();
    if (!mounted) return;

    setState(() {
      _res = res;
      _display = res.roll;
      _rolling = false;
      _history.insert(0, res);
      if (_history.length > 12) _history.removeLast();
    });
    holdBalance(res.balance);
    reportRound(bet: _bet, payout: res.payout);
    if (res.win) {
      AppHaptics.medium();
      AppSound.play(Sfx.win);
    } else {
      AppSound.play(Sfx.lose);
    }
    _settle(res.balance);
  }

  Future<void> _settle(double expected) async {
    for (var i = 0; i < 30; i++) {
      if (!mounted) return;
      if ((walletBalance - expected).abs() < .005) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (mounted && !_rolling) releaseBalance();
  }

  @override
  Widget build(BuildContext context) {
    final res = _res;
    final balance = watchBalance(context);
    final tone = res == null ? AppColors.text : (res.win ? AppColors.green : AppColors.loss);
    final shown = _display;

    return GameScaffold(
      title: 'Dice',
      balance: balance,
      lowBalance: walletBalance < _minBet && !_rolling,
      glowColor: res == null ? AppColors.blue : tone,
      onHelp: () => openGuide(context, GameType.dice),
      onVerify: () => openFairness(context, roundId: res?.roundId),
      stage: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        children: [
          SizedBox(
            height: 34,
            child: _history.isEmpty
                ? Align(alignment: Alignment.centerLeft, child: Text('Your last rolls show here', style: AppText.body(12, color: AppColors.textFaint)))
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
                        child: Text(h.roll.toStringAsFixed(2), style: AppText.number(12, color: c, weight: FontWeight.w700)),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 18),
          Column(
            children: [
              Text(_rolling ? 'ROLLING' : (res == null ? 'READY' : 'YOU ROLLED'), style: AppText.label(color: res == null ? AppColors.textDim : tone)),
              const SizedBox(height: 6),
              Text(
                shown == null ? '--.--' : shown.toStringAsFixed(2),
                style: AppText.number(64, color: _rolling ? AppColors.textSoft : tone, shadows: res == null ? null : AppText.glow(tone, opacity: .4)),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 28,
                child: res == null
                    ? null
                    : StatusPill(label: res.win ? 'WIN · ×${res.multiplier.toStringAsFixed(4)}' : 'LOSS', color: tone),
              ),
            ],
          ),
          const SizedBox(height: 22),
          DiceTrack(target: _target, over: _over, onChanged: _setTarget, lastRoll: res?.roll, enabled: !_rolling),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [for (final t in const ['0', '25', '50', '75', '100']) Text(t, style: AppText.body(11, color: AppColors.textFaint))],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: StatTile(label: 'Multiplier', value: '${_mult.toStringAsFixed(4)}×')),
              const SizedBox(width: 10),
              Expanded(child: StatTile(label: _over ? 'Roll over' : 'Roll under', value: _target.toStringAsFixed(2))),
              const SizedBox(width: 10),
              Expanded(child: StatTile(label: 'Win chance', value: '${_chance.toStringAsFixed(2)}%')),
            ],
          ),
          const SizedBox(height: 14),
          IgnorePointer(
            ignoring: _rolling,
            child: SegmentedToggle<bool>(
              options: const [SegmentOption(value: false, label: 'Roll under'), SegmentOption(value: true, label: 'Roll over')],
              selected: _over,
              onChanged: (v) {
                AppHaptics.selection();
                setState(() => _over = v);
              },
            ),
          ),
        ],
      ),
      panel: BetPanel(
        bet: _bet,
        minBet: _minBet,
        maxBet: _maxBet,
        onBetChanged: _setBet,
        busy: _rolling,
        actionLabel: res == null ? 'ROLL' : 'ROLL AGAIN',
        onAction: _rolling ? null : _roll,
        extra: res != null
            ? Column(
                children: [
                  WinBanner(
                    amount: res.payout - _lastBet,
                    lossLabel: res.win ? 'WIN' : 'ROUND LOST',
                    caption: res.win ? 'Paid ×${res.multiplier.toStringAsFixed(4)}' : null,
                  ),
                  const SizedBox(height: 6),
                  PressScale(
                    onTap: () => openFairness(context, roundId: res.roundId),
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
                  Text('Profit on win', style: AppText.body(13, color: AppColors.textDim)),
                  Text('+${formatCredits(_profit)}', style: AppText.number(14, color: AppColors.green)),
                ],
              ),
      ),
    );
  }
}
