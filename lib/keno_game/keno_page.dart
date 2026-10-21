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
import 'keno_api.dart';

String _x(double v) => v == 0 ? '0x' : '${v.toStringAsFixed(v >= 100 || v == v.roundToDouble() ? 0 : 2)}x';

/// Keno. Pick up to ten numbers from forty. Ten are drawn on the server.
class KenoPage extends StatefulWidget {
  const KenoPage({super.key, this.info});

  final GameInfo? info;

  @override
  State<KenoPage> createState() => _KenoPageState();
}

class _KenoPageState extends State<KenoPage> with GameSessionMixin<KenoPage> {
  @override
  GameType get guideType => GameType.keno;

  static const _chips = <double>[10, 50, 100, 500, 1000];

  late final KenoApi _api;
  KenoConfig? _config;
  bool _loadFailed = false;

  double _bet = 100;
  final Set<int> _picks = {};
  KenoResult? _result;
  // Numbers revealed so far while the draw plays out.
  final Set<int> _shown = {};
  bool _busy = false;

  double get _minBet => widget.info?.minBet ?? 10;
  double get _maxBet => maxBetFor(widget.info?.maxBet ?? 2000);
  int get _pool => _config?.pool ?? 40;
  int get _maxPicks => _config?.maxPicks ?? 10;

  @override
  void initState() {
    super.initState();
    _api = KenoApi(context.read<ApiClient>());
    _bet = _bet.clamp(_minBet, _maxBet).toDouble();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadFailed = false);
    try {
      final c = await _api.config();
      if (!mounted) return;
      setState(() => _config = c);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _release(double expected) async {
    for (var i = 0; i < 30; i++) {
      if (!mounted) return;
      if ((walletBalance - expected).abs() < .005) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (mounted && !_busy) releaseBalance();
  }

  void _toggle(int n) {
    if (_busy) return;
    if (_result != null) {
      setState(() {
        _result = null;
        _shown.clear();
      });
    }
    if (_picks.contains(n)) {
      AppSound.play(Sfx.tap);
      setState(() => _picks.remove(n));
    } else if (_picks.length >= _maxPicks) {
      showToast(context, 'You can pick up to $_maxPicks numbers.');
    } else {
      AppSound.play(Sfx.chip);
      AppHaptics.selection();
      setState(() => _picks.add(n));
    }
  }

  void _auto() {
    if (_busy) return;
    final rnd = math.Random();
    final all = [for (var i = 1; i <= _pool; i++) i]..shuffle(rnd);
    final want = _picks.isEmpty ? 5 : _picks.length;
    AppSound.play(Sfx.tap);
    setState(() {
      _result = null;
      _shown.clear();
      _picks
        ..clear()
        ..addAll(all.take(want));
    });
  }

  void _clear() {
    if (_busy) return;
    AppSound.play(Sfx.tap);
    setState(() {
      _picks.clear();
      _result = null;
      _shown.clear();
    });
  }

  Future<void> _play() async {
    if (_busy) return;
    if (_picks.isEmpty) {
      showToast(context, 'Pick at least one number.');
      return;
    }
    if (!checkCanPlay()) return;
    if (_bet > walletBalance) {
      showNoCredits(context, needed: _bet);
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
      _shown.clear();
    });
    holdBalance(walletBalance - _bet);
    AppSound.play(Sfx.chip);
    AppHaptics.light();
    try {
      final r = await _api.play(_bet, _picks.toList()..sort());
      if (!mounted) return;
      for (final n in r.drawn) {
        if (!mounted) return;
        setState(() => _shown.add(n));
        if (r.picks.contains(n)) {
          AppSound.play(Sfx.win);
          AppHaptics.selection();
        } else {
          AppSound.play(Sfx.tap);
        }
        await Future<void>.delayed(const Duration(milliseconds: 170));
      }
      if (!mounted) return;
      setState(() {
        _result = r;
        _busy = false;
      });
      holdBalance(r.balance);
      reportRound(bet: r.bet, payout: r.payout);
      if (r.isWin) {
        AppSound.play(r.multiplier >= 5 ? Sfx.bigWin : Sfx.win);
        AppHaptics.medium();
      } else if (r.isPush) {
        AppSound.play(Sfx.tap);
      } else {
        AppSound.play(Sfx.lose);
      }
      _release(r.balance);
    } catch (e) {
      releaseBalance();
      AppSound.play(Sfx.error);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _shown.clear();
      });
      if (failKind(e) == FailKind.noRounds) {
        showRoundsSheet(context);
      } else if (failKind(e) == FailKind.noCredits) {
        showNoCredits(context, needed: _bet);
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
    final tone = r == null ? AppColors.blue : (r.isWin ? AppColors.green : (r.isPush ? AppColors.gold : AppColors.loss));

    return GameScaffold(
      title: 'Keno',
      balance: balance,
      lowBalance: walletBalance < _minBet && !_busy,
      glowColor: tone,
      onHelp: () => openGuide(context, GameType.keno),
      onVerify: () => openFairness(context, roundId: r?.roundId),
      stage: _config == null ? _loading() : _board(r),
      panel: _panel(r, tone),
    );
  }

  Widget _loading() => Center(
        child: _loadFailed
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Could not load Keno.', style: AppText.body(14, color: AppColors.textMuted)),
                const SizedBox(height: 12),
                AppButton(label: 'Try again', variant: AppButtonVariant.outline, height: 44, fontSize: 14, onPressed: _load),
              ])
            : const AppLoader(),
      );

  Widget _board(KenoResult? r) {
    final cols = 8;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Center(
        child: AspectRatio(
          aspectRatio: cols / (_pool / cols),
          child: GridView.count(
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: cols,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            children: [for (var n = 1; n <= _pool; n++) _cell(n)],
          ),
        ),
      ),
    );
  }

  Widget _cell(int n) {
    final picked = _picks.contains(n);
    final drawn = _shown.contains(n);
    final hit = picked && drawn;
    final Color fill;
    final Color border;
    final Color text;
    if (hit) {
      fill = AppColors.green;
      border = AppColors.green;
      text = AppColors.onAccent;
    } else if (drawn) {
      fill = AppColors.loss.withValues(alpha: .22);
      border = AppColors.loss;
      text = AppColors.text;
    } else if (picked) {
      fill = AppColors.blue.withValues(alpha: .22);
      border = AppColors.blue;
      text = AppColors.text;
    } else {
      fill = AppColors.surface;
      border = AppColors.line;
      text = AppColors.textMuted;
    }
    return PressScale(
      onTap: _busy ? null : () => _toggle(n),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(12), border: Border.all(color: border, width: picked || drawn ? 1.6 : 1)),
        child: Text('$n', style: AppText.number(15, color: text)),
      ),
    );
  }

  /// The pay table for the current number of picks, with the reached row lit.
  Widget _payTable(KenoResult? r) {
    final k = _picks.length;
    final table = _config?.tables[k];
    if (k == 0 || table == null) {
      return SizedBox(height: 46, child: Center(child: Text('Pick 1 to $_maxPicks numbers', style: AppText.body(13, color: AppColors.textMuted))));
    }
    final reached = r?.hits.length;
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: table.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, hits) {
          final on = reached == hits;
          final pays = table[hits] > 0;
          return Container(
            width: 58,
            decoration: BoxDecoration(
              color: on ? (pays ? AppColors.green : AppColors.loss).withValues(alpha: .2) : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: on ? (pays ? AppColors.green : AppColors.loss) : AppColors.line, width: on ? 1.6 : 1),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('$hits HIT', style: AppText.label(size: 9, color: AppColors.textMuted)),
              Text(_x(table[hits]), style: AppText.number(13, color: pays ? AppColors.gold : AppColors.textFaint)),
            ]),
          );
        },
      ),
    );
  }

  Widget _panel(KenoResult? r, Color tone) {
    final children = <Widget>[
      if (r != null) ...[
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.isWin ? 'YOU WON' : (r.isPush ? 'BET RETURNED' : 'NO WIN'), style: AppText.label(color: tone)),
              const SizedBox(height: 2),
              Text('${r.hits.length} of ${r.picks.length} hit  ·  ${_x(r.multiplier)}', style: AppText.body(12, color: AppColors.textMuted)),
            ]),
          ),
          Text(formatSigned(r.net), style: AppText.number(26, color: tone, shadows: r.isWin ? AppText.glow(tone, opacity: .4) : null)),
        ]),
        const SizedBox(height: 10),
      ],
      _payTable(r),
      const SizedBox(height: 10),
      BetChipPicker(values: _chips, selected: _bet, size: 46, onSelected: (v) {
        if (_busy) return;
        AppSound.play(Sfx.chip);
        setState(() => _bet = v.clamp(_minBet, _maxBet).toDouble());
      }),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: AppButton(label: 'Auto', variant: AppButtonVariant.outline, height: 56, fontSize: 14, onPressed: _busy ? null : _auto)),
        const SizedBox(width: 8),
        Expanded(child: AppButton(label: 'Clear', variant: AppButtonVariant.outline, height: 56, fontSize: 14, onPressed: _busy || _picks.isEmpty ? null : _clear)),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: AppButton(
            label: r == null ? 'PLAY' : 'PLAY AGAIN',
            sublabel: 'BET ${formatCredits(_bet, decimals: 0)}',
            variant: AppButtonVariant.success,
            height: 56,
            fontSize: 16,
            loading: _busy,
            onPressed: _busy || _picks.isEmpty ? null : _play,
          ),
        ),
      ]),
      if (r != null && !_busy)
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
