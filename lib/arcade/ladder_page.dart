import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../core/api/api_client.dart';
import '../games/game_support.dart';
import '../model/model.dart';
import '../pages/how_to_play_page.dart';
import '../rounds/rounds_sheet.dart';
import 'arcade_api.dart';

String _x(double v) => '${v.toStringAsFixed(v < 100 && v != v.roundToDouble() ? 2 : 0)}x';

class _Skin {
  const _Skin({required this.safe, required this.bad, required this.action, required this.tiles});

  final String safe;
  final String bad;

  /// Label of the big button when the game has one move (Cross, Pump).
  final String action;

  /// true: pick one of several tiles on each level. false: a single button.
  final bool tiles;
}

const _skins = <String, _Skin>{
  'tower': _Skin(safe: '💎', bad: '💥', action: '', tiles: true),
  'moles': _Skin(safe: '🌱', bad: '🐹', action: '', tiles: true),
  'chicken': _Skin(safe: '🐔', bad: '💥', action: 'CROSS', tiles: false),
  'pump': _Skin(safe: '🎈', bad: '💥', action: 'PUMP', tiles: false),
};

/// Tower, Chicken Road, Pump and Moles. Every safe move raises the multiplier. Cash out before a bad one.
class LadderPage extends StatefulWidget {
  const LadderPage({super.key, required this.info});

  final GameInfo info;

  @override
  State<LadderPage> createState() => _LadderPageState();
}

class _LadderPageState extends State<LadderPage> with GameSessionMixin<LadderPage> {
  @override
  GameType get guideType => widget.info.type;

  static const _chips = <double>[10, 50, 100, 500, 1000];

  String get _id => widget.info.id;
  _Skin get _skin => _skins[_id] ?? _skins['tower']!;

  late final ArcadeApi _api;
  ArcadeConfig? _config;
  bool _loadFailed = false;
  bool _resuming = true;
  bool _busy = false;
  double _bet = 100;
  String _difficulty = 'easy';
  LadderState? _round;
  int? _tapped;

  double get _minBet => widget.info.minBet;
  double get _maxBet => maxBetFor(widget.info.maxBet);
  bool get _playing => _round?.playing == true;

  @override
  void initState() {
    super.initState();
    _api = ArcadeApi(context.read<ApiClient>(), _id);
    _bet = _bet.clamp(_minBet, _maxBet).toDouble();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadFailed = false);
    try {
      final c = await _api.config();
      if (!mounted) return;
      setState(() {
        _config = c;
        if (!c.difficulties.contains(_difficulty) && c.difficulties.isNotEmpty) _difficulty = c.difficulties.first;
      });
      _resume();
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _resume() async {
    try {
      final s = await _api.active();
      if (!mounted) return;
      if (s != null) {
        holdBalance(s.balance);
        setState(() {
          _round = s;
          _difficulty = s.difficulty;
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

  Future<void> _start() async {
    if (_busy || _playing || _resuming || _config == null) return;
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
      final s = await _api.start(_bet, _difficulty);
      if (!mounted) return;
      setState(() {
        _round = s;
        _busy = false;
      });
      holdBalance(s.balance);
      _release(s.balance);
    } on LadderResume catch (r) {
      if (!mounted) return;
      setState(() {
        _round = r.state;
        _difficulty = r.state.difficulty;
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

  Future<void> _step(int pick) async {
    final r = _round;
    if (_busy || r == null || !r.playing) return;
    setState(() {
      _busy = true;
      _tapped = pick;
    });
    AppHaptics.selection();
    try {
      _apply(await _api.step(r.roundId, pick));
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
    if (r.picks.isEmpty) {
      showToast(context, 'Make one move first.');
      return;
    }
    setState(() => _busy = true);
    AppHaptics.medium();
    try {
      _apply(await _api.cashOut(r.roundId));
    } catch (e) {
      AppSound.play(Sfx.error);
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, failText(e), error: true);
    }
  }

  void _apply(LadderState s) {
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
    if (res.hit) {
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
    final res = _round?.result;
    final tone = res == null ? AppColors.gold : (res.isWin ? AppColors.green : AppColors.loss);
    return GameScaffold(
      title: widget.info.name,
      balance: balance,
      lowBalance: walletBalance < _minBet && !_busy && !_playing,
      glowColor: tone,
      onHelp: () => openGuide(context, widget.info.type),
      onVerify: () => openFairness(context, roundId: _round?.roundId),
      stage: _stage(),
      panel: _panel(res, tone),
    );
  }

  /// The levels as the player sees them before and during a round.
  LadderLevels? get _preview => _config?.levels(_difficulty);

  Widget _stage() {
    if (_config == null) {
      return Center(
        child: _loadFailed
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Could not load the game.', style: AppText.body(14, color: AppColors.textMuted)),
                const SizedBox(height: 12),
                AppButton(label: 'Try again', variant: AppButtonVariant.outline, height: 44, fontSize: 14, onPressed: _load),
              ])
            : const AppLoader(),
      );
    }
    return _skin.tiles ? _tilesStage() : _singleStage();
  }

  Widget _tilesStage() {
    final r = _round;
    final pre = _preview!;
    final cols = r?.cols ?? pre.cols;
    final mults = r?.multipliers ?? pre.multipliers;
    final level = r == null ? 0 : (r.playing ? r.picks.length : r.picks.length);
    final over = r != null && !r.playing;
    final failed = over && r.result?.hit == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(children: [
        for (var row = cols.length - 1; row >= 0; row--)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 56, child: Text(_x(mults[row]), style: AppText.number(12, color: r != null && row == level && r.playing ? AppColors.gold : AppColors.textDim))),
                for (var c = 0; c < cols[row]; c++) ...[
                  if (c > 0) const SizedBox(width: 6),
                  Expanded(child: _tile(r, row, c, level, over, failed)),
                ],
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _tile(LadderState? r, int row, int c, int level, bool over, bool failed) {
    final picked = r != null && row < r.picks.length && r.picks[row] == c;
    final isBad = r != null && over && r.badMask.length > row && (r.badMask[row] >> c) & 1 == 1;
    final current = r != null && r.playing && row == level;
    String face = '';
    Color fill = AppColors.surface;
    Color line = AppColors.line;
    if (picked && !(isBad)) {
      face = _skin.safe;
      fill = AppColors.green.withValues(alpha: .22);
      line = AppColors.green;
    } else if (isBad) {
      face = _skin.bad;
      fill = AppColors.loss.withValues(alpha: picked ? .35 : .12);
      line = picked ? AppColors.loss : AppColors.line;
    } else if (current) {
      fill = AppColors.gold.withValues(alpha: .10);
      line = AppColors.gold.withValues(alpha: .6);
    }
    return PressScale(
      onTap: current && !_busy ? () => _step(c) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: _tapped == c && current && _busy ? AppColors.gold.withValues(alpha: .25) : fill, borderRadius: BorderRadius.circular(12), border: Border.all(color: line, width: picked ? 1.6 : 1)),
        child: FittedBox(child: Padding(padding: const EdgeInsets.all(4), child: Text(face, style: const TextStyle(fontSize: 20)))),
      ),
    );
  }

  Widget _singleStage() {
    final r = _round;
    final pre = _preview!;
    final mults = r?.multipliers ?? pre.multipliers;
    final safe = r == null ? 0 : r.safeCount;
    final over = r != null && !r.playing;
    final failed = over && r.result?.hit == true;
    final isPump = _id == 'pump';
    final next = safe < mults.length ? mults[safe] : null;
    final scale = isPump ? (.7 + .5 * (safe / (mults.isEmpty ? 1 : mults.length))) : 1.0;
    return Column(children: [
      Expanded(
        child: Center(
          child: AnimatedScale(
            scale: failed ? 1.25 : scale,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(failed ? _skin.bad : (isPump ? _skin.safe : (r == null ? '🐣' : _skin.safe)), style: TextStyle(fontSize: isPump ? 110 : 84)),
              const SizedBox(height: 8),
              Text(r == null ? '1.00x' : _x(r.multiplier == 0 ? 1 : (failed ? 0 : r.multiplier)), style: AppText.number(40, color: failed ? AppColors.loss : AppColors.text)),
              if (next != null && !over) Text('Next ${_x(next)}', style: AppText.body(13, color: AppColors.textDim)),
            ]),
          ),
        ),
      ),
      if (!isPump)
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (var i = 0; i < mults.length; i++)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i < safe ? AppColors.green.withValues(alpha: .22) : (i == safe && !over ? AppColors.gold.withValues(alpha: .15) : AppColors.surface),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: i < safe ? AppColors.green : (i == safe && !over ? AppColors.gold : AppColors.line)),
                  ),
                  child: Text(_x(mults[i]), style: AppText.number(12, color: i < safe ? AppColors.green : AppColors.textMuted)),
                ),
            ],
          ),
        ),
      const SizedBox(height: 10),
    ]);
  }

  // ------------------------------------------------------------------- panel

  Widget _chipRow() {
    final d = _config?.difficulties ?? const <String>[];
    return Row(children: [
      for (var i = 0; i < d.length; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(
          child: PressScale(
            onTap: _busy || _playing
                ? null
                : () {
                    AppSound.play(Sfx.tap);
                    setState(() {
                      _difficulty = d[i];
                      _round = null;
                    });
                  },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _difficulty == d[i] ? AppColors.gold.withValues(alpha: .16) : AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _difficulty == d[i] ? AppColors.gold : AppColors.line, width: _difficulty == d[i] ? 1.6 : 1),
              ),
              child: FittedBox(child: Text(d[i].toUpperCase(), style: AppText.label(color: _difficulty == d[i] ? AppColors.gold : AppColors.textMuted, size: 10))),
            ),
          ),
        ),
      ],
    ]);
  }

  Widget _panel(LadderResult? res, Color tone) {
    final r = _round;
    final children = <Widget>[];
    if (r != null && r.playing) {
      children.add(Row(children: [
        Expanded(child: Text('${_x(r.multiplier)}  ·  ${r.safeCount} safe', style: AppText.label(color: AppColors.gold))),
        Text(formatCredits(r.cashValue, decimals: 0), style: AppText.number(22, color: AppColors.gold)),
      ]));
      children.add(const SizedBox(height: 10));
      if (!_skin.tiles) {
        children.add(AppButton(label: _skin.action, variant: AppButtonVariant.success, height: 56, fontSize: 16, loading: _busy, onPressed: _busy ? null : () => _step(0)));
        children.add(const SizedBox(height: 8));
      }
      children.add(AppButton(
        label: 'CASH OUT',
        sublabel: r.picks.isEmpty ? null : formatCredits(r.cashValue, decimals: 0),
        variant: _skin.tiles ? AppButtonVariant.success : AppButtonVariant.outline,
        height: _skin.tiles ? 56 : 48,
        fontSize: 15,
        onPressed: _busy || r.picks.isEmpty ? null : _cashOut,
        onDisabledTap: r.picks.isEmpty ? () => showToast(context, 'Make one move first.') : null,
      ));
    } else {
      if (r != null && res != null) {
        children.add(Row(children: [
          Expanded(child: Text(res.hit ? 'BUSTED' : 'CASHED OUT', style: AppText.label(color: tone))),
          Text(formatSigned(res.net), style: AppText.number(26, color: tone, shadows: res.isWin ? AppText.glow(tone, opacity: .4) : null)),
        ]));
        children.add(Align(alignment: Alignment.centerLeft, child: Text(res.label, style: AppText.body(12, color: AppColors.textDim))));
        children.add(const SizedBox(height: 10));
      }
      if (_config != null) {
        children.add(_chipRow());
        children.add(const SizedBox(height: 12));
      }
      children.add(BetChipPicker(values: _chips, selected: _bet, size: 50, onSelected: (v) {
        if (_busy) return;
        AppSound.play(Sfx.chip);
        setState(() => _bet = v.clamp(_minBet, _maxBet).toDouble());
      }));
      children.add(const SizedBox(height: 12));
      children.add(AppButton(
        label: r == null ? 'START' : 'PLAY AGAIN',
        sublabel: 'BET ${formatCredits(_bet, decimals: 0)}',
        variant: AppButtonVariant.success,
        height: 56,
        fontSize: 16,
        loading: _busy,
        onPressed: _busy || _resuming || _config == null ? null : _start,
      ));
      if (r != null)
        children.add(PressScale(
          onTap: () => openFairness(context, roundId: r.roundId),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Verify this round', style: AppText.body(13, weight: FontWeight.w600, color: AppColors.green, decoration: TextDecoration.underline)),
          ),
        ));
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
