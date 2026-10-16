import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../core/api/api_client.dart';
import '../games/game_support.dart';
import '../model/model.dart';
import '../user/bloc/profile_cubit.dart';
import '../user/data/user_repository.dart';
import 'roulette_api.dart';
import '../pages/how_to_play_page.dart';

enum _Phase { betting, spinning, result }

class _Placement {
  const _Placement(this.type, this.value, this.amount);
  final String type;
  final int? value;
  final double amount;
  String get key => value == null ? type : '$type:$value';
}

/// G2. European roulette. One spin per round, decided on the server.
class RoulettePage extends StatefulWidget {
  const RoulettePage({super.key, this.info});

  final GameInfo? info;

  @override
  State<RoulettePage> createState() => _RoulettePageState();
}

class _RoulettePageState extends State<RoulettePage> with TickerProviderStateMixin, GameSessionMixin<RoulettePage> {
  @override
  GameType get guideType => GameType.roulette;

  static const _chips = <double>[10, 50, 100, 500, 1000];
  static const double _seg = 2 * math.pi / 37;

  late final RouletteApi _api;
  late final Ticker _free = createTicker(_onFree);
  late final AnimationController _land = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400));

  _Phase _phase = _Phase.betting;
  double _chip = 100;
  final List<_Placement> _placed = [];
  List<_Placement> _lastBets = [];
  RouletteResult? _res;
  double _rotation = 0;
  Duration _lastTick = Duration.zero;
  final List<int> _history = [];

  double get _total => _placed.fold(0.0, (a, p) => a + p.amount);
  double get _maxTotal => maxBetFor(widget.info?.maxBet ?? 100000);

  @override
  void initState() {
    super.initState();
    _api = RouletteApi(context.read<ApiClient>());
    _land.addListener(() {
      if (mounted) setState(() {});
    });
    _loadHistory();
  }

  @override
  void dispose() {
    _free.dispose();
    _land.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final rounds = await context
          .read<UserRepository>()
          .watchRounds(profile.state.user.id, game: GameType.roulette, limit: 12)
          .first
          .timeout(const Duration(seconds: 4));
      if (!mounted || _history.isNotEmpty) return;
      setState(() {
        for (final r in rounds) {
          final n = r.details['number'];
          if (n is num) _history.add(n.toInt());
        }
      });
    } catch (_) {}
  }

  void _onFree(Duration t) {
    final dt = (t - _lastTick).inMicroseconds / 1e6;
    _lastTick = t;
    if (dt <= 0 || dt > .25) return;
    setState(() => _rotation += dt * 7);
  }

  // ---------------------------------------------------------------- betting

  void _place(String type, [int? value]) {
    if (_phase == _Phase.spinning) return;
    if (_phase == _Phase.result) _newBets();
    if (_total + _chip > _maxTotal) {
      showToast(context, 'Your highest bet is ${formatCredits(_maxTotal, decimals: 0)} credits.', error: true);
      return;
    }
    AppSound.play(Sfx.chip);
    AppHaptics.selection();
    setState(() => _placed.add(_Placement(type, value, _chip)));
  }

  void _undo() {
    if (_phase != _Phase.betting || _placed.isEmpty) return;
    AppSound.play(Sfx.tap, volume: .5);
    setState(() => _placed.removeLast());
  }

  void _clear() {
    if (_phase != _Phase.betting) return;
    setState(_placed.clear);
  }

  void _newBets() {
    setState(() {
      _phase = _Phase.betting;
      _placed.clear();
      _res = null;
    });
  }

  double _stake(String key) => _placed.fold(0.0, (a, p) => p.key == key ? a + p.amount : a);

  // ------------------------------------------------------------------- spin

  Future<void> _spin({List<_Placement>? rebet}) async {
    if (_phase == _Phase.spinning) return;
    if (rebet != null) {
      _placed
        ..clear()
        ..addAll(rebet);
    }
    if (_placed.isEmpty) {
      showToast(context, 'Place a bet first. Tap a number or a section.');
      return;
    }
    if (!checkCanPlay()) return;
    final total = _total;
    if (total > walletBalance) {
      showNoCredits(context, needed: total);
      return;
    }
    final bets = [for (final p in _placed) RouletteBet(p.type, p.value, p.amount)];
    _lastBets = List.of(_placed);
    setState(() {
      _phase = _Phase.spinning;
      _res = null;
    });
    holdBalance(walletBalance - total);
    AppSound.play(Sfx.rouletteSpin);
    AppHaptics.light();
    _lastTick = Duration.zero;
    _free.start();

    final started = DateTime.now();
    final RouletteResult res;
    try {
      res = await _api.spin(bets);
    } catch (e) {
      _free.stop();
      releaseBalance();
      AppSound.play(Sfx.error);
      if (!mounted) return;
      setState(() => _phase = _Phase.betting);
      if (failKind(e) == FailKind.noCredits) {
        showNoCredits(context, needed: total);
      } else {
        showToast(context, failText(e), error: true);
      }
      return;
    }
    final elapsed = DateTime.now().difference(started);
    if (elapsed < const Duration(milliseconds: 900)) await Future<void>.delayed(const Duration(milliseconds: 900) - elapsed);
    _free.stop();
    if (!mounted) return;

    // Slow down and land with the winning pocket under the pointer.
    final idx = kWheelOrder.indexOf(res.number);
    final r0 = _rotation;
    const turns = 3 * 2 * math.pi;
    final delta = (((-idx * _seg - r0) % (2 * math.pi)) + 2 * math.pi) % (2 * math.pi);
    final r1 = r0 + turns + delta;
    final tween = Tween<double>(begin: r0, end: r1);
    _land.reset();
    void onLand() => _rotation = tween.transform(Curves.easeOutCubic.transform(_land.value));
    _land.addListener(onLand);
    await _land.forward().orCancel.catchError((Object _) => null);
    _land.removeListener(onLand);
    if (!mounted) return;
    _rotation = r1;

    AppSound.play(Sfx.ballDrop);
    setState(() {
      _res = res;
      _phase = _Phase.result;
      _history.insert(0, res.number);
      if (_history.length > 12) _history.removeLast();
    });
    holdBalance(res.balance);
    reportRound(bet: res.totalBet, payout: res.payout);
    if (res.payout > res.totalBet) {
      AppHaptics.medium();
      AppSound.play(Sfx.win);
      if (res.payout / res.totalBet >= 10) {
        AppSound.play(Sfx.bigWin);
        unawaited(showBigWin(context, amount: res.net, title: 'BIG WIN', multiplier: res.payout / res.totalBet, caption: '${res.number} ${res.color}'));
      }
    } else if (res.payout < res.totalBet) {
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
    if (mounted && _phase != _Phase.spinning) releaseBalance();
  }

  // ---------------------------------------------------------------- widgets

  @override
  Widget build(BuildContext context) {
    final balance = watchBalance(context);
    final res = _res;
    final win = res != null && res.payout > res.totalBet;
    final push = res != null && res.payout == res.totalBet;
    final tone = res == null ? AppColors.green : (win ? AppColors.green : (push ? AppColors.gold : AppColors.loss));

    return GameScaffold(
      title: 'Roulette',
      balance: balance,
      lowBalance: walletBalance < 10 && _phase != _Phase.spinning,
      glowColor: AppColors.green,
      onHelp: () => openGuide(context, GameType.roulette),
      onVerify: () => openFairness(context, roundId: _phase == _Phase.result ? res?.roundId : null),
      stage: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          SizedBox(
            height: 34,
            child: _history.isEmpty
                ? Align(alignment: Alignment.centerLeft, child: Text('Winning numbers show here', style: AppText.body(12, color: AppColors.textFaint)))
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _history.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) => _HistoryDot(number: _history[i]),
                  ),
          ),
          const SizedBox(height: 10),
          Center(child: RouletteWheel(rotation: _rotation, result: _phase == _Phase.result ? res?.number : null, size: 210)),
          const SizedBox(height: 10),
          Center(
            child: StatusPill(
              label: switch (_phase) {
                _Phase.betting => 'PLACE YOUR BETS',
                _Phase.spinning => 'NO MORE BETS',
                _Phase.result => res == null ? '' : '${res.number} ${res.color.toUpperCase()}',
              },
              color: _phase == _Phase.result ? tone : (_phase == _Phase.spinning ? AppColors.gold : AppColors.green),
              pulsing: _phase == _Phase.spinning,
            ),
          ),
          const SizedBox(height: 14),
          _table(),
        ],
      ),
      panel: _panel(res, win, push),
    );
  }

  Widget _table() {
    return LayoutBuilder(builder: (context, box) {
      final zeroW = 34.0;
      final gap = 3.0;
      final cw = ((box.maxWidth - zeroW - gap * 13) / 12);
      final win = _res?.winningKeys ?? const <String>{};
      final hit = _phase == _Phase.result ? _res?.number : null;

      Widget cell(int n) {
        final key = 'straight:$n';
        final st = _stake(key);
        return Padding(
          padding: EdgeInsets.all(gap / 2),
          child: RouletteNumberCell(
            number: n,
            size: cw,
            selected: hit == n || (hit != null && win.contains(key)),
            chipAmount: st > 0 ? st : null,
            onTap: () => _place('straight', n),
          ),
        );
      }

      final zeroStake = _stake('straight:0');
      return Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.all(gap / 2),
                child: SizedBox(
                  width: zeroW - gap,
                  height: (cw + gap) * 3 - gap,
                  child: PressScale(
                    onTap: () => _place('straight', 0),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.greenDark,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: hit == 0 ? AppColors.gold : AppColors.line, width: hit == 0 ? 2 : 1),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('0', style: AppText.number(14, weight: FontWeight.w700)),
                          if (zeroStake > 0) Text(zeroStake.toStringAsFixed(0), style: AppText.body(9, weight: FontWeight.w800, color: AppColors.gold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    for (final row in const [3, 2, 1])
                      Row(children: [for (var c = 0; c < 12; c++) Expanded(child: Center(child: cell(c * 3 + row)))]),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(children: [
            for (var d = 1; d <= 3; d++) ...[
              if (d > 1) const SizedBox(width: 6),
              Expanded(child: _OutsideCell(label: d == 1 ? '1st 12' : (d == 2 ? '2nd 12' : '3rd 12'), stake: _stake('dozen:$d'), won: win.contains('dozen:$d'), onTap: () => _place('dozen', d))),
            ],
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _OutsideCell(label: '1-18', stake: _stake('low'), won: win.contains('low'), onTap: () => _place('low'))),
            const SizedBox(width: 6),
            Expanded(child: _OutsideCell(label: 'Even', stake: _stake('even'), won: win.contains('even'), onTap: () => _place('even'))),
            const SizedBox(width: 6),
            Expanded(child: _OutsideCell(label: 'Red', color: const Color(0xFFC62B2E), stake: _stake('red'), won: win.contains('red'), onTap: () => _place('red'))),
            const SizedBox(width: 6),
            Expanded(child: _OutsideCell(label: 'Black', color: const Color(0xFF2A2A2E), stake: _stake('black'), won: win.contains('black'), onTap: () => _place('black'))),
            const SizedBox(width: 6),
            Expanded(child: _OutsideCell(label: 'Odd', stake: _stake('odd'), won: win.contains('odd'), onTap: () => _place('odd'))),
            const SizedBox(width: 6),
            Expanded(child: _OutsideCell(label: '19-36', stake: _stake('high'), won: win.contains('high'), onTap: () => _place('high'))),
          ]),
        ],
      );
    });
  }

  Widget _panel(RouletteResult? res, bool win, bool push) {
    Widget body;
    if (_phase == _Phase.result && res != null) {
      final tone = win ? AppColors.green : (push ? AppColors.gold : AppColors.loss);
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(win ? 'YOU WON' : (push ? 'BET RETURNED' : 'ROUND LOST'), style: AppText.label(color: tone)),
                    const SizedBox(height: 2),
                    Text('${res.number} ${res.color} · ${_wonText(res)}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.body(12, color: AppColors.textMuted)),
                  ],
                ),
              ),
              Text(formatSigned(res.net), style: AppText.number(26, color: tone, shadows: win ? AppText.glow(tone, opacity: .4) : null)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: AppButton(label: 'New bets', variant: AppButtonVariant.outline, height: 56, fontSize: 15, onPressed: _newBets)),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: AppButton(label: 'REBET AND SPIN', variant: AppButtonVariant.success, height: 56, fontSize: 15, onPressed: () => _spin(rebet: _lastBets))),
            ],
          ),
          const SizedBox(height: 6),
          PressScale(
            onTap: () => openFairness(context, roundId: res.roundId),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Verify this round', style: AppText.body(13, weight: FontWeight.w600, color: AppColors.green, decoration: TextDecoration.underline)),
            ),
          ),
        ],
      );
    } else {
      final spinning = _phase == _Phase.spinning;
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text.rich(TextSpan(children: [TextSpan(text: 'Total bet  ', style: AppText.body(13, color: AppColors.textDim)), TextSpan(text: formatCredits(_total, decimals: 0), style: AppText.number(16, color: AppColors.gold))]))),
              PillButton(label: 'Undo', height: 36, fontSize: 12, onPressed: spinning || _placed.isEmpty ? null : _undo),
              const SizedBox(width: 8),
              PillButton(label: 'Clear', height: 36, fontSize: 12, onPressed: spinning || _placed.isEmpty ? null : _clear),
            ],
          ),
          const SizedBox(height: 12),
          BetChipPicker(values: _chips, selected: _chip, size: 54, onSelected: (v) {
            AppSound.play(Sfx.chip);
            setState(() => _chip = v);
          }),
          const SizedBox(height: 14),
          AppButton(label: 'SPIN', variant: AppButtonVariant.success, height: 60, loading: spinning, onPressed: spinning ? null : _spin),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: AppColors.sheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: AnimatedSize(duration: const Duration(milliseconds: 180), alignment: Alignment.topCenter, child: body),
    );
  }

  /// "straight up ×36" style text for the best winning bet.
  String _wonText(RouletteResult res) {
    if (res.winningKeys.isEmpty) return 'no winning bets';
    final names = <String>[];
    for (final k in res.winningKeys) {
      final parts = k.split(':');
      final b = RouletteBet(parts[0], parts.length > 1 ? int.tryParse(parts[1]) : null, 0);
      names.add(b.type == 'straight' ? 'straight up ×${b.returns}' : '${b.name} ×${b.returns}');
    }
    return names.take(2).join(', ');
  }
}

class _HistoryDot extends StatelessWidget {
  const _HistoryDot({required this.number});
  final int number;

  @override
  Widget build(BuildContext context) {
    final c = number == 0 ? AppColors.greenDark : (kRouletteReds.contains(number) ? const Color(0xFFC62B2E) : const Color(0xFF2A2A2E));
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c, border: Border.all(color: AppColors.lineStrong)),
      child: Text('$number', style: AppText.number(11, weight: FontWeight.w700)),
    );
  }
}

class _OutsideCell extends StatelessWidget {
  const _OutsideCell({required this.label, required this.stake, required this.onTap, this.color, this.won = false});

  final String label;
  final double stake;
  final VoidCallback onTap;
  final Color? color;
  final bool won;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color ?? AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: won ? AppColors.gold : AppColors.line, width: won ? 2 : 1),
            ),
            child: FittedBox(fit: BoxFit.scaleDown, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(label, style: AppText.body(11, weight: FontWeight.w700, color: AppColors.textSoft)))),
          ),
          if (stake > 0)
            Positioned(
              right: -3,
              top: -5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(10)),
                child: Text(stake.toStringAsFixed(0), style: AppText.body(9, weight: FontWeight.w800, color: AppColors.bg, height: 1)),
              ),
            ),
        ],
      ),
    );
  }
}
