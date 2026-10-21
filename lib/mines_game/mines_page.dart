import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../core/api/api_client.dart';
import '../games/game_support.dart';
import '../model/model.dart';
import '../pages/how_to_play_page.dart';
import '../rounds/rounds_sheet.dart';
import 'mines_api.dart';

String _x(double v) => 'x${v.toStringAsFixed(v >= 100 ? 0 : 2)}';

/// Mines. A 5 by 5 board hides mines. The board is drawn and kept on the server.
class MinesPage extends StatefulWidget {
  const MinesPage({super.key, this.info});

  final GameInfo? info;

  @override
  State<MinesPage> createState() => _MinesPageState();
}

class _MinesPageState extends State<MinesPage> with GameSessionMixin<MinesPage> {
  @override
  GameType get guideType => GameType.mines;

  static const _chips = <double>[10, 50, 100, 500, 1000];
  static const _mineChoices = <int>[1, 3, 5, 10, 15, 24];

  late final MinesApi _api;

  double _bet = 100;
  int _mines = 3;
  MinesState? _round;
  bool _busy = false;
  bool _resuming = true;
  int? _tapped;

  double get _minBet => widget.info?.minBet ?? 10;
  double get _maxBet => maxBetFor(widget.info?.maxBet ?? 2000);
  bool get _playing => _round?.playing == true;
  MinesResult? get _result => _round?.result;

  @override
  void initState() {
    super.initState();
    _api = MinesApi(context.read<ApiClient>());
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
          _mines = s.mines;
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
      final s = await _api.start(_bet, _mines);
      if (!mounted) return;
      setState(() {
        _round = s;
        _busy = false;
      });
      holdBalance(s.balance);
      _release(s.balance);
    } on MinesResume catch (r) {
      if (!mounted) return;
      setState(() {
        _round = r.state;
        _mines = r.state.mines;
        _busy = false;
      });
      holdBalance(r.state.balance);
      _release(r.state.balance);
      showToast(context, 'You still have a round in play. Finish it first.');
    } catch (e) {
      releaseBalance();
      AppSound.play(Sfx.error);
      if (!mounted) return;
      setState(() => _busy = false);
      if (failKind(e) == FailKind.noRounds) {
        showRoundsSheet(context);
      } else if (failKind(e) == FailKind.noCredits) {
        showNoCredits(context, needed: _bet);
      } else {
        showToast(context, failText(e), error: true);
      }
    }
  }

  Future<void> _open(int tile) async {
    final r = _round;
    if (_busy || r == null || !r.playing || r.revealed.contains(tile)) return;
    setState(() {
      _busy = true;
      _tapped = tile;
    });
    AppHaptics.selection();
    try {
      final s = await _api.reveal(r.roundId, tile);
      _apply(s);
    } catch (e) {
      AppSound.play(Sfx.error);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _tapped = null;
      });
      showToast(context, failText(e), error: true);
    }
  }

  Future<void> _cashOut() async {
    final r = _round;
    if (_busy || r == null || !r.playing) return;
    if (r.safeCount == 0) {
      showToast(context, 'Open at least one tile first.');
      return;
    }
    setState(() => _busy = true);
    AppHaptics.medium();
    try {
      final s = await _api.cashOut(r.roundId);
      _apply(s);
    } catch (e) {
      AppSound.play(Sfx.error);
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, failText(e), error: true);
    }
  }

  void _apply(MinesState s) {
    if (!mounted) return;
    setState(() {
      _round = s;
      _busy = false;
      _tapped = null;
    });
    holdBalance(s.balance);
    final res = s.result;
    if (res == null) {
      AppSound.play(Sfx.coin);
      return;
    }
    reportRound(bet: s.bet, payout: res.payout);
    if (res.hit != null) {
      AppSound.play(Sfx.bust);
      AppHaptics.medium();
    } else {
      AppSound.play(res.multiplier >= 5 ? Sfx.bigWin : Sfx.cashOut);
      AppHaptics.medium();
    }
    _release(s.balance);
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final balance = watchBalance(context);
    final r = _round;
    final res = _result;
    final tone = res == null ? AppColors.mint : (res.isWin ? AppColors.green : AppColors.loss);

    return GameScaffold(
      title: 'Mines',
      balance: balance,
      lowBalance: walletBalance < _minBet && !_playing && !_busy,
      glowColor: tone,
      onHelp: () => openGuide(context, GameType.mines),
      onVerify: () => openFairness(context, roundId: res != null ? r?.roundId : null),
      banner: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: AppColors.surfaceAlt,
        alignment: Alignment.center,
        child: Text('OPEN GEMS  ·  AVOID MINES  ·  CASH OUT ANY TIME', style: AppText.label(color: AppColors.mint, size: 10)),
      ),
      stage: LayoutBuilder(builder: (context, box) {
        final side = math.min(380.0, math.max(120.0, math.min(box.maxWidth - 32, box.maxHeight - 90)));
        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: side,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _stats(r),
                const SizedBox(height: 14),
                SizedBox(width: side, height: side, child: _board(r, side)),
              ]),
            ),
          ),
        );
      }),
      panel: _panel(r, res, tone),
    );
  }

  Widget _stats(MinesState? r) {
    final playing = r?.playing == true;
    final mult = r?.multiplier ?? 1.0;
    final next = r?.nextMultiplier;
    final mines = r?.mines ?? _mines;
    Widget cell(String label, String value, {Color? color}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: AppText.label(size: 9)),
              const SizedBox(height: 3),
              FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: AppText.number(15, color: color ?? AppColors.text))),
            ]),
          ),
        );
    return Row(children: [
      cell('MINES', '$mines'),
      const SizedBox(width: 8),
      cell('MULTIPLIER', _x(mult), color: playing && (r?.safeCount ?? 0) > 0 ? AppColors.green : null),
      const SizedBox(width: 8),
      cell('NEXT TILE', next == null ? '-' : _x(next), color: AppColors.gold),
    ]);
  }

  Widget _board(MinesState? r, double side) {
    const gap = 8.0;
    final over = r != null && !r.playing;
    return Column(children: [
      for (var row = 0; row < 5; row++) ...[
        if (row > 0) const SizedBox(height: gap),
        Expanded(
          child: Row(children: [
            for (var col = 0; col < 5; col++) ...[
              if (col > 0) const SizedBox(width: gap),
              Expanded(child: _tile(r, row * 5 + col, over)),
            ],
          ]),
        ),
      ],
    ]);
  }

  Widget _tile(MinesState? r, int i, bool over) {
    final opened = r?.revealed.contains(i) == true;
    final isMine = over && (r?.minesAt.contains(i) == true);
    final hit = isMine && _result?.hit == i;
    final waiting = _busy && _tapped == i;

    Color fill = AppColors.surfaceAlt;
    Color border = AppColors.line;
    Widget? icon;
    if (hit) {
      fill = AppColors.loss.withValues(alpha: .25);
      border = AppColors.loss;
      icon = Icon(Icons.warning_amber_rounded, color: AppColors.loss, size: 26);
    } else if (opened) {
      fill = AppColors.green.withValues(alpha: .16);
      border = AppColors.green.withValues(alpha: .7);
      icon = Icon(Icons.diamond_rounded, color: AppColors.green, size: 26);
    } else if (isMine) {
      icon = Icon(Icons.warning_amber_rounded, color: AppColors.textFaint, size: 22);
    } else if (over) {
      icon = Icon(Icons.diamond_outlined, color: AppColors.textFaint.withValues(alpha: .6), size: 20);
    }
    final canTap = _playing && !opened && !_busy;
    return Semantics(
      button: canTap,
      label: opened ? 'Safe tile' : (isMine ? 'Mine' : 'Closed tile ${i + 1}'),
      child: PressScale(
        onTap: canTap ? () => _open(i) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(color: waiting ? AppColors.surface : fill, borderRadius: BorderRadius.circular(14), border: Border.all(color: border, width: opened || hit ? 1.6 : 1)),
          alignment: Alignment.center,
          child: waiting ? const SizedBox(height: 18, child: FittedBox(child: AppLoader())) : AnimatedScale(scale: icon == null ? .6 : 1, duration: const Duration(milliseconds: 180), curve: Curves.easeOutBack, child: icon ?? const SizedBox.shrink()),
        ),
      ),
    );
  }

  Widget _minePicker() {
    return Row(children: [
      Text('MINES', style: AppText.label()),
      const SizedBox(width: 12),
      Expanded(
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final m in _mineChoices)
            PressScale(
              onTap: () {
                AppSound.play(Sfx.tap);
                setState(() => _mines = m);
              },
              child: Container(
                constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: _mines == m ? AppColors.mint.withValues(alpha: .18) : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _mines == m ? AppColors.mint : AppColors.line),
                ),
                child: Text('$m', style: AppText.number(13, color: _mines == m ? AppColors.mint : AppColors.text)),
              ),
            ),
        ]),
      ),
    ]);
  }

  Widget _panel(MinesState? r, MinesResult? res, Color tone) {
    Widget body;
    if (_playing && r != null) {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        AppButton(
          label: 'CASH OUT',
          sublabel: r.safeCount == 0 ? 'OPEN A TILE FIRST' : formatCredits(r.cashValue, decimals: 0),
          variant: AppButtonVariant.success,
          height: 64,
          cooldown: Duration.zero,
          loading: _busy && _tapped == null,
          onDisabledTap: _busy ? null : _cashOut,
          onPressed: _busy || r.safeCount == 0 ? null : _cashOut,
        ),
      ]);
    } else if (res != null && r != null) {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(res.hit != null ? 'MINE HIT' : 'CASHED OUT', style: AppText.label(color: tone)),
              const SizedBox(height: 2),
              Text(res.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.body(12, color: AppColors.textMuted)),
            ]),
          ),
          Text(formatSigned(res.net), style: AppText.number(26, color: tone, shadows: res.isWin ? AppText.glow(tone, opacity: .4) : null)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: AppButton(label: 'Change bet', variant: AppButtonVariant.outline, height: 56, fontSize: 15, onPressed: () => setState(() => _round = null))),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: AppButton(label: 'PLAY AGAIN', variant: AppButtonVariant.success, height: 56, fontSize: 15, loading: _busy, onPressed: _busy ? null : _start)),
        ]),
        const SizedBox(height: 6),
        PressScale(
          onTap: () => openFairness(context, roundId: r.roundId),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Verify this round', style: AppText.body(13, weight: FontWeight.w600, color: AppColors.green, decoration: TextDecoration.underline)),
          ),
        ),
      ]);
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        _minePicker(),
        const SizedBox(height: 14),
        BetChipPicker(values: _chips, selected: _bet, size: 54, onSelected: (v) {
          AppSound.play(Sfx.chip);
          setState(() => _bet = v.clamp(_minBet, _maxBet).toDouble());
        }),
        const SizedBox(height: 14),
        AppButton(label: 'START', sublabel: 'BET ${formatCredits(_bet, decimals: 0)}', variant: AppButtonVariant.success, height: 64, loading: _busy || _resuming, onPressed: _busy || _resuming ? null : _start),
      ]);
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppColors.sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: AnimatedSize(duration: const Duration(milliseconds: 180), alignment: Alignment.topCenter, child: body),
    );
  }
}
