import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../core/api/api_client.dart';
import '../games/game_support.dart';
import '../model/model.dart';
import '../pages/how_to_play_page.dart';
import '../rounds/rounds_sheet.dart';
import 'hilo_api.dart';

String _x(double v) => 'x${v.toStringAsFixed(v >= 100 ? 0 : 2)}';
String _pct(double v) => '${(v * 100).toStringAsFixed(v < .1 ? 1 : 0)}%';

/// Hi-Lo. Guess whether the next card is higher or lower. The deck stays on the server.
class HiLoPage extends StatefulWidget {
  const HiLoPage({super.key, this.info});

  final GameInfo? info;

  @override
  State<HiLoPage> createState() => _HiLoPageState();
}

class _HiLoPageState extends State<HiLoPage> with GameSessionMixin<HiLoPage> {
  @override
  GameType get guideType => GameType.hilo;

  static const _chips = <double>[10, 50, 100, 500, 1000];

  late final HiLoApi _api;

  double _bet = 100;
  HiLoState? _round;
  bool _busy = false;
  bool _resuming = true;

  double get _minBet => widget.info?.minBet ?? 10;
  double get _maxBet => maxBetFor(widget.info?.maxBet ?? 2000);
  bool get _playing => _round?.playing == true;
  HiLoResult? get _result => _round?.result;

  @override
  void initState() {
    super.initState();
    _api = HiLoApi(context.read<ApiClient>());
    _bet = _bet.clamp(_minBet, _maxBet).toDouble();
    _resume();
  }

  Future<void> _resume() async {
    try {
      final s = await _api.active();
      if (!mounted) return;
      if (s != null) {
        holdBalance(s.balance);
        setState(() {
          _round = s;
          _bet = s.bet;
        });
        _release(s.balance);
      }
    } catch (_) {}
    _resuming = false;
    if (mounted) setState(() {});
  }

  Future<void> _release(double expected) async {
    for (var i = 0; i < 30; i++) {
      if (!mounted) return;
      if ((walletBalance - expected).abs() < .005) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (mounted && !_busy) releaseBalance();
  }

  void _fail(Object e, {double? needed}) {
    AppSound.play(Sfx.error);
    if (!mounted) return;
    setState(() => _busy = false);
    if (failKind(e) == FailKind.noRounds) {
      showRoundsSheet(context);
    } else if (failKind(e) == FailKind.noCredits) {
      showNoCredits(context, needed: needed ?? _bet);
    } else {
      showToast(context, failText(e), error: true);
    }
  }

  // ------------------------------------------------------------------ actions

  Future<void> _start() async {
    if (_busy || _playing || _resuming) return;
    if (!checkCanPlay()) return;
    if (_bet > walletBalance) {
      showNoCredits(context, needed: _bet);
      return;
    }
    setState(() {
      _busy = true;
      _round = null;
    });
    holdBalance(walletBalance - _bet);
    AppSound.play(Sfx.chip);
    AppHaptics.light();
    try {
      final s = await _api.start(_bet);
      if (!mounted) return;
      AppSound.play(Sfx.card);
      setState(() {
        _round = s;
        _busy = false;
      });
      holdBalance(s.balance);
      _release(s.balance);
    } on HiLoResume catch (r) {
      if (!mounted) return;
      setState(() {
        _round = r.state;
        _bet = r.state.bet;
        _busy = false;
      });
      holdBalance(r.state.balance);
      _release(r.state.balance);
      showToast(context, 'You still have a round in play. Finish it first.');
    } catch (e) {
      releaseBalance();
      _fail(e);
    }
  }

  Future<void> _guess(String choice) async {
    final r = _round;
    if (_busy || r == null || !r.playing) return;
    setState(() => _busy = true);
    AppSound.play(Sfx.card);
    AppHaptics.selection();
    try {
      final s = await _api.guess(r.roundId, choice);
      if (!mounted) return;
      setState(() {
        _round = s;
        _busy = false;
      });
      holdBalance(s.balance);
      final res = s.result;
      if (res != null) {
        reportRound(bet: s.bet, payout: res.payout);
        if (res.lost) {
          AppSound.play(Sfx.lose);
        } else {
          AppSound.play(res.multiplier >= 5 ? Sfx.bigWin : Sfx.win);
          AppHaptics.medium();
        }
        _release(s.balance);
      } else {
        AppSound.play(Sfx.cardFlip);
      }
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _cash() async {
    final r = _round;
    if (_busy || r == null || !r.playing || r.correct < 1) return;
    setState(() => _busy = true);
    try {
      final s = await _api.cashOut(r.roundId);
      if (!mounted) return;
      setState(() {
        _round = s;
        _busy = false;
      });
      holdBalance(s.balance);
      final res = s.result;
      if (res != null) reportRound(bet: s.bet, payout: res.payout);
      AppSound.play(Sfx.win);
      AppHaptics.medium();
      _release(s.balance);
    } catch (e) {
      _fail(e);
    }
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final balance = watchBalance(context);
    final s = _round;
    final res = _result;
    final tone = res == null ? AppColors.mint : (res.lost ? AppColors.loss : AppColors.green);

    return GameScaffold(
      title: 'Hi-Lo',
      balance: balance,
      lowBalance: walletBalance < _minBet && !_busy && !_playing,
      glowColor: tone,
      onHelp: () => openGuide(context, GameType.hilo),
      onVerify: () => openFairness(context, roundId: s?.roundId),
      stage: _stage(s),
      panel: _panel(s, tone),
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

  Widget _stage(HiLoState? s) {
    if (_resuming) return const Center(child: AppLoader());
    if (s == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.swap_vert_rounded, size: 56, color: AppColors.mint),
          const SizedBox(height: 12),
          Text('Higher or lower?', style: AppText.body(18, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Choose your bet and start.', style: AppText.body(13, color: AppColors.textMuted)),
        ]),
      );
    }
    final past = s.history.length > 5 ? s.history.sublist(s.history.length - 5) : s.history;
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 62,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final c in past)
                Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: Opacity(opacity: .55, child: _face(c, 38))),
            ]),
          ),
          const SizedBox(height: 14),
          TweenAnimationBuilder<double>(
            key: ValueKey('${s.roundId}_${s.history.length}'),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            builder: (context, t, child) => Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.translate(offset: Offset(0, -24 * (1 - t)), child: child),
            ),
            child: _face(s.card, 110),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.line)),
            child: Text(
              s.correct == 0 ? 'Make your first guess' : '${s.correct} correct  ·  ${_x(s.multiplier)}',
              style: AppText.label(color: s.correct == 0 ? AppColors.textMuted : AppColors.gold, size: 11),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _choice(String label, IconData icon, HiLoOption o, String key) {
    final on = o.available && !_busy;
    final color = key == 'higher' ? AppColors.green : AppColors.blue;
    return Expanded(
      child: PressScale(
        onTap: on ? () => _guess(key) : null,
        child: Opacity(
          opacity: o.available ? 1 : .4,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(16), border: Border.all(color: color, width: 1.4)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: color, size: 26),
              Text(label, style: AppText.label(color: color, size: 12)),
              const SizedBox(height: 2),
              Text(o.available ? '${_pct(o.chance)}  ·  ${_x(o.multiplier!)}' : 'Not possible', style: AppText.body(11, color: AppColors.textMuted)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _panel(HiLoState? s, Color tone) {
    final res = _result;
    final children = <Widget>[];
    if (res != null) {
      children
        ..add(Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(res.lost ? 'WRONG GUESS' : 'CASHED OUT', style: AppText.label(color: tone)),
              const SizedBox(height: 2),
              Text(res.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(12, color: AppColors.textMuted)),
            ]),
          ),
          Text(formatSigned(res.net), style: AppText.number(26, color: tone, shadows: res.lost ? null : AppText.glow(tone, opacity: .4))),
        ]))
        ..add(const SizedBox(height: 12));
    }
    if (s != null && s.playing) {
      children
        ..add(Row(children: [
          _choice('HIGHER', Icons.keyboard_arrow_up_rounded, s.higher, 'higher'),
          const SizedBox(width: 10),
          _choice('LOWER', Icons.keyboard_arrow_down_rounded, s.lower, 'lower'),
        ]))
        ..add(const SizedBox(height: 12))
        ..add(AppButton(
          label: 'CASH OUT',
          sublabel: s.correct < 1 ? 'GUESS ONCE FIRST' : formatCredits(s.cashValue, decimals: 0),
          variant: AppButtonVariant.success,
          height: 56,
          fontSize: 16,
          loading: _busy,
          onPressed: _busy || s.correct < 1 ? null : _cash,
        ));
    } else {
      children
        ..add(BetChipPicker(values: _chips, selected: _bet, size: 50, onSelected: (v) {
          if (_busy) return;
          AppSound.play(Sfx.chip);
          setState(() => _bet = v.clamp(_minBet, _maxBet).toDouble());
        }))
        ..add(const SizedBox(height: 12))
        ..add(AppButton(
          label: s == null ? 'START' : 'PLAY AGAIN',
          sublabel: 'BET ${formatCredits(_bet, decimals: 0)}',
          variant: AppButtonVariant.success,
          height: 56,
          fontSize: 16,
          loading: _busy,
          onPressed: _busy || _resuming ? null : _start,
        ));
      if (s != null) {
        children.add(PressScale(
          onTap: () => openFairness(context, roundId: s.roundId),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Verify this round', style: AppText.body(13, weight: FontWeight.w600, color: AppColors.green, decoration: TextDecoration.underline)),
          ),
        ));
      }
    }
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
