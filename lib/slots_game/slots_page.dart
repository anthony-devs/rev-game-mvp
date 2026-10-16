// Golden Reels: 3 reels, 1 payline.
//
// Server-driven: the page only talks to [SlotsServer]. Swap [MockSlotsServer]
// for a class that calls your edge function (GET config, POST spin).
//
// Open it with:
//   Navigator.push(context, MaterialPageRoute(builder: (_) => const SlotsPage()));

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rev_game_mvp/components/components.dart';

import 'reel_widget.dart';
import 'slots_models.dart';
import 'slots_painters.dart';
import 'slots_server.dart';
import 'slots_theme.dart';
import 'slots_widgets.dart';
import 'symbol_view.dart';

enum SlotsPhase { idle, spinning, win, bigWin }

class SlotsPage extends StatefulWidget {
  const SlotsPage({super.key, this.server});
  final SlotsServer? server;

  @override
  State<SlotsPage> createState() => _SlotsPageState();
}

class _SlotsPageState extends State<SlotsPage> with TickerProviderStateMixin {
  late final SlotsServer _server = widget.server ?? MockSlotsServer();
  SlotsConfig? _cfg;

  final _reelKeys = List.generate(3, (_) => GlobalKey<ReelWidgetState>());
  final _initial = const [
    [SlotSymbol.diamond, SlotSymbol.seven, SlotSymbol.bar],
    [SlotSymbol.bell, SlotSymbol.bar, SlotSymbol.cherry],
    [SlotSymbol.cherry, SlotSymbol.bell, SlotSymbol.diamond],
  ];

  SlotsPhase _phase = SlotsPhase.idle;
  bool _sheetOpen = false, _turbo = false, _auto = false, _skip = false;
  double _balance = 0, _bet = 100, _win = 0;
  String _plate = 'Match 3 on the line to win';
  SpinResult? _last;
  final List<int> _history = [0, 2, 0, 10, 0, 0, 25, 0];
  List<SlotSymbol> _payline = [SlotSymbol.seven, SlotSymbol.bar, SlotSymbol.bell];

  late final AnimationController _fx = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  late final AnimationController _count = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    _server.fetchConfig().then((c) {
      if (!mounted) return;
      setState(() {
        _cfg = c;
        _balance = c.startBalance;
        _bet = c.defaultBet;
      });
    });
  }

  @override
  void dispose() {
    _fx.dispose();
    _count.dispose();
    super.dispose();
  }

  bool get _isWinLike => _phase == SlotsPhase.win || _phase == SlotsPhase.bigWin;
  bool get _spinning => _phase == SlotsPhase.spinning;
  bool get _cantAfford => _balance < _bet;

  // ------ Bet controls ------
  void _setBet(double v) {
    if (_spinning || _cfg == null) return;
    setState(() => _bet = v.clamp(_cfg!.minBet, _cfg!.maxBet).roundToDouble());
  }

  void _step(int dir) {
    final steps = _cfg!.betSteps;
    if (dir > 0) {
      final i = steps.indexWhere((s) => s > _bet);
      _setBet(i == -1 ? steps.last : steps[i]);
    } else {
      final j = steps.lastIndexWhere((s) => s < _bet);
      _setBet(j == -1 ? steps.first : steps[j]);
    }
  }

  // ------ Spin flow ------
  Future<void> _spin() async {
    if (_spinning || _cfg == null) return;
    if (_cantAfford) {
      _showNoCredits();
      return;
    }
    HapticFeedback.lightImpact();
    _skip = false;
    setState(() {
      _phase = SlotsPhase.spinning;
      _win = 0;
      _plate = 'Spinning...';
    });
    _count.value = 0;
    for (final k in _reelKeys) {
      k.currentState?.startSpin();
    }

    final started = DateTime.now();
    final SpinResult res;
    try {
      res = await _server.spin(_bet);
    } catch (_) {
      if (!mounted) return;
      for (var i = 0; i < 3; i++) {
        _reelKeys[i].currentState?.stopTo([SlotSymbol.cherry, _payline[i], SlotSymbol.bar], fast: true);
      }
      setState(() {
        _phase = SlotsPhase.idle;
        _plate = 'Something went wrong. Try again';
      });
      if (_cantAfford) _showNoCredits();
      return;
    }
    if (!mounted) return;
    setState(() => _balance = res.balanceAfterBet);

    final minSpin = Duration(milliseconds: _turbo ? 350 : 900);
    final elapsed = DateTime.now().difference(started);
    if (!_skip && elapsed < minSpin) await Future<void>.delayed(minSpin - elapsed);
    if (!mounted) return;

    final gap = _turbo ? 60 : 160;
    final stops = <Future<void>>[];
    for (var i = 0; i < 3; i++) {
      stops.add(Future<void>.delayed(Duration(milliseconds: _skip ? 0 : gap * i), () {
        return _reelKeys[i].currentState?.stopTo(res.columns[i], fast: _skip || _turbo);
      }));
    }
    await Future.wait(stops);
    if (!mounted) return;

    _last = res;
    _payline = [for (final c in res.columns) c[1]];
    _history.insert(0, res.multiplier);
    if (_history.length > 12) _history.removeLast();

    if (res.isWin) {
      final big = res.multiplier >= _cfg!.bigWinMultiplier;
      HapticFeedback.mediumImpact();
      setState(() {
        _phase = big ? SlotsPhase.bigWin : SlotsPhase.win;
        _plate = res.label;
        _balance = res.balanceAfter;
      });
      _count.forward(from: 0);
      if (big) {
        HapticFeedback.heavyImpact();
        _auto = false; // big wins always wait for Continue
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 1400));
        if (!mounted) return;
        if (_phase == SlotsPhase.win) setState(() => _phase = SlotsPhase.idle);
      }
    } else {
      setState(() {
        _phase = SlotsPhase.idle;
        _plate = 'No win this time';
      });
    }
    _afterRound();
  }

  void _afterRound() async {
    if (_phase == SlotsPhase.bigWin) return;
    if (_cantAfford) {
      _auto = false;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted && _cantAfford) _showNoCredits();
      return;
    }
    if (_auto) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (mounted && _auto && !_spinning && !_sheetOpen) _spin();
    }
  }

  void _dismissBigWin() {
    setState(() {
      _phase = SlotsPhase.idle;
      _plate = 'Match 3 on the line to win';
    });
    _afterRound();
  }

  Future<void> _getCredits() async {
    final b = await _server.topUp();
    if (!mounted) return;
    setState(() => _balance = b);
  }

  // ------ Sheets ------
  Future<void> _openSheet(String? title, Widget child) async {
    _sheetOpen = true;
    await showAppBottomSheet<void>(context, title: title, child: child);
    _sheetOpen = false;
  }

  void _showFairness() => _openSheet(
        'Provably fair',
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: InfoCard(
            icon: Icons.verified_user_outlined,
            color: AppColors.green,
            message: 'Every result is decided on the server before the reels stop. '
                'Your device only plays the animation.',
          ),
        ),
      );

  void _showPaytable(SlotsConfig cfg) {
    Widget stat(String k, String v) => Expanded(child: StatTile(label: k, value: v));
    _openSheet(
      'Paytable & rules',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PAYOUTS - MATCH ON THE PAYLINE', style: AppText.label()),
          const SizedBox(height: 10),
          for (final row in cfg.payRows) ...[
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(children: [
                SizedBox(
                  width: 112,
                  child: Row(children: [
                    for (final s in row.symbols) ...[SymbolView(s, size: 30), const SizedBox(width: 4)],
                  ]),
                ),
                Expanded(child: Text(row.label, style: AppText.body(14, weight: FontWeight.w600, color: AppColors.textSoft))),
                Text('x${row.multiplier}', style: AppText.number(17, color: AppColors.gold)),
              ]),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 10),
          Text('HOW TO PLAY', style: AppText.label()),
          const SizedBox(height: 6),
          Text(
            'Set your bet, then press SPIN. Three matching symbols on the payline pay your bet times the multiplier. '
            'The server decides every result before the reels stop.',
            style: AppText.body(14, weight: FontWeight.w400, color: AppColors.textSoft, height: 1.45),
          ),
          const SizedBox(height: 16),
          Row(children: [stat('Min bet', fmt(cfg.minBet)), const SizedBox(width: 8), stat('Max bet', fmt(cfg.maxBet))]),
          const SizedBox(height: 8),
          Row(children: [stat('Max win', fmt(cfg.maxWin)), const SizedBox(width: 8), stat('Return to player', '${(cfg.rtp * 100).round()}%')]),
          const SizedBox(height: 12),
          Text('Demo credits only. Values load from this game\'s config.', style: AppText.body(11, weight: FontWeight.w400, color: AppColors.textDim)),
        ],
      ),
    );
  }

  void _showNoCredits() {
    final cfg = _cfg;
    if (cfg == null || _sheetOpen) return;
    final lower = _balance.floorToDouble().clamp(cfg.minBet, cfg.maxBet).toDouble();
    final canLower = _balance.floorToDouble() >= cfg.minBet;
    _openSheet(
      null,
      Builder(builder: (sheetContext) {
        return Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.lossStrong.withValues(alpha: .14),
                border: Border.all(color: AppColors.lossStrong.withValues(alpha: .5)),
              ),
              child: const Icon(Icons.error_outline_rounded, size: 28, color: AppColors.loss),
            ),
            const SizedBox(height: 14),
            Text('Not enough credits', style: AppText.body(22, weight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'You have ${fmt(_balance)} credits but this bet is ${fmt(_bet)}. Lower your bet or get more demo credits.',
              textAlign: TextAlign.center,
              style: AppText.body(14, weight: FontWeight.w400, color: AppColors.textMuted, height: 1.45),
            ),
            const SizedBox(height: 22),
            AppButton(
              label: 'Get demo credits',
              variant: AppButtonVariant.gold,
              onPressed: () async {
                await _getCredits();
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
            ),
            if (canLower) ...[
              const SizedBox(height: 12),
              AppButton(
                label: 'Lower bet to ${fmt(lower)}',
                variant: AppButtonVariant.outline,
                height: 52,
                onPressed: () {
                  setState(() => _bet = lower);
                  Navigator.pop(sheetContext);
                },
              ),
            ],
          ],
        );
      }),
    );
  }

  // ------ UI ------
  @override
  Widget build(BuildContext context) {
    final cfg = _cfg;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: cfg == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.gold))
          : Stack(
              children: [
                Positioned.fill(
                  child: GlowBackground(
                    glowColor: AppColors.purple,
                    glowOpacity: .34,
                    center: const Alignment(0, -.19),
                    radius: .85,
                    child: SafeArea(
                      child: Column(
                        children: [
                          GameTopBar(
                            title: 'Slots',
                            balance: _balance,
                            low: _cantAfford && !_spinning,
                            onBack: () => Navigator.maybePop(context),
                            onVerify: _showFairness,
                            actions: [
                              IconSquareButton(
                                icon: Icons.info_outline_rounded,
                                semanticLabel: 'Game info',
                                onPressed: () => _showPaytable(cfg),
                              ),
                            ],
                          ),
                          HistoryStrip(
                            values: [for (final m in _history) m.toDouble()],
                            decimals: 0,
                            colorFor: (v) => v == 0 ? AppColors.loss : (v >= 25 ? AppColors.gold : AppColors.green),
                          ),
                          Expanded(
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.contain,
                                child: SizedBox(width: 372, height: 489, child: _machineWithFx(cfg)),
                              ),
                            ),
                          ),
                          _dock(cfg),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_phase == SlotsPhase.bigWin && _last != null) Positioned.fill(child: _bigWin()),
              ],
            ),
    );
  }

  Widget _machineWithFx(SlotsConfig cfg) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (_isWinLike)
          Positioned(
            left: -74,
            top: -36,
            width: 520,
            height: 520,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _fx,
                builder: (_, __) => CustomPaint(
                  painter: RaysPainter(onDeg: 6, periodDeg: 18, alpha: 0.16, fade: 0.95, rotation: _fx.value * 360),
                ),
              ),
            ),
          ),
        Positioned.fill(child: _machine(cfg)),
        if (_isWinLike) ..._sparkles(),
      ],
    );
  }

  // Machine
  Widget _machine(SlotsConfig cfg) {
    final win = _isWinLike;
    final lineColor = win ? kGold : const Color(0xFFFFE9A8);
    final lineOpacity = win ? 1.0 : (_spinning ? 0.18 : 0.3);
    final label = _spinning ? 'Reels spinning' : 'Reels show ${_payline.map((s) => symbolNames[s]).join(', ')}';

    return Semantics(
      label: label,
      child: ClipRect(
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          Positioned(
            left: 0,
            top: 0,
            width: 372,
            height: 573,
            child: Image.asset('assets/slots/machine_clean.png', fit: BoxFit.fill, filterQuality: FilterQuality.medium),
          ),

          // Marquee sign
          Positioned(
            left: 64,
            top: 10,
            width: 248,
            height: 48,
            child: Transform.rotate(
              angle: -3 * math.pi / 180,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Golden',
                    style: GoogleFonts.yellowtail(fontSize: 38, height: 1, color: const Color(0xFFFFD36B), shadows: [
                      Shadow(color: kGold, blurRadius: win ? 10 : 6),
                      Shadow(color: const Color(0xD9FFC83D), blurRadius: win ? 26 : 14),
                    ])),
                const SizedBox(width: 8),
                Text('Reels',
                    style: GoogleFonts.yellowtail(fontSize: 38, height: 1, color: const Color(0xFFE6BBFF), shadows: [
                      Shadow(color: AppColors.purple, blurRadius: win ? 10 : 6),
                      Shadow(color: const Color(0xE6B26BFF), blurRadius: win ? 26 : 14),
                    ])),
              ]),
            ),
          ),

          // Reels
          for (var i = 0; i < 3; i++)
            Positioned(
              left: [53.0, 149.0, 245.0][i],
              top: 121,
              child: ReelWidget(key: _reelKeys[i], initial: _initial[i], highlight: win),
            ),

          // Payline + markers
          Positioned(
            left: 44,
            top: 183,
            width: 288,
            height: 3,
            child: Opacity(
              opacity: lineOpacity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: lineColor,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: win ? const [BoxShadow(color: Color(0xE6FFC83D), blurRadius: 12, spreadRadius: 2)] : null,
                ),
              ),
            ),
          ),
          Positioned(left: 36, top: 176, width: 9, height: 14, child: CustomPaint(painter: TrianglePainter(pointsRight: true))),
          Positioned(left: 327, top: 176, width: 9, height: 14, child: CustomPaint(painter: TrianglePainter(pointsRight: false))),

          // Result plate
          Positioned(left: 40, top: 262, width: 292, height: 28, child: ResultPlate(text: _plate, win: win)),

          // Wood panel: LEDs + bet buttons
          Positioned(
            left: 12,
            top: 333,
            width: 348,
            height: 122,
            child: Column(children: [
              SizedBox(
                height: 64,
                child: Row(children: [
                  Expanded(
                    flex: 112,
                    child: AnimatedBuilder(
                      animation: _count,
                      builder: (_, __) {
                        final shown = _isWinLike && _last != null ? _last!.payout * Curves.easeOutCubic.transform(_count.value) : _win;
                        return Led(
                          label: 'WIN',
                          value: fmt(shown),
                          color: win ? const Color(0xFFFFD36B) : const Color(0xFF8F6E3A),
                          glow: win ? const Shadow(color: Color(0xE6FFC83D), blurRadius: 14) : null,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 100,
                    child: Led(
                      label: 'BET',
                      value: fmt(_bet),
                      color: const Color(0xFFFFB23D),
                      glow: const Shadow(color: Color(0xB3FFB23D), blurRadius: 8),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              Opacity(
                opacity: _spinning ? 0.45 : 1,
                child: IgnorePointer(
                  ignoring: _spinning,
                  child: SizedBox(
                    height: 44,
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      BrassButton(width: 44, icon: Icons.remove_rounded, semanticLabel: 'Decrease bet', onPressed: () => _step(-1)),
                      BrassButton(label: 'MIN', fontSize: 13, semanticLabel: 'Minimum bet', onPressed: () => _setBet(cfg.minBet)),
                      BrassButton(label: '1/2', fontSize: 15, semanticLabel: 'Half the bet', onPressed: () => _setBet(_bet / 2)),
                      BrassButton(label: '2x', fontSize: 15, semanticLabel: 'Double the bet', onPressed: () => _setBet(_bet * 2)),
                      BrassButton(label: 'MAX', fontSize: 13, semanticLabel: 'Maximum bet', onPressed: () => _setBet(cfg.maxBet)),
                      BrassButton(width: 44, icon: Icons.add_rounded, semanticLabel: 'Increase bet', onPressed: () => _step(1)),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // Sparkles (positions are relative to the machine box)
  List<Widget> _sparkles() {
    const pts = [
      [15.0, 144.0, 20.0], [341.0, 162.0, 16.0], [95.0, 96.0, 14.0],
      [261.0, 90.0, 18.0], [43.0, 274.0, 14.0], [321.0, 268.0, 18.0],
    ];
    return [
      for (var i = 0; i < pts.length; i++)
        Positioned(
          left: pts[i][0],
          top: pts[i][1],
          width: pts[i][2],
          height: pts[i][2],
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _fx,
              builder: (_, child) {
                final t = math.sin((_fx.value * 6 + i * 0.37) * 2 * math.pi);
                return Opacity(
                  opacity: 0.65 + 0.35 * t.abs(),
                  child: Transform.scale(scale: 0.8 + 0.25 * t.abs(), child: child),
                );
              },
              child: CustomPaint(painter: SparklePainter()),
            ),
          ),
        ),
    ];
  }

  // Dock
  Widget _dock(SlotsConfig cfg) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.sheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppColors.line)),
        boxShadow: [BoxShadow(color: Color(0x73000000), blurRadius: 32, offset: Offset(0, -8))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              DockToggleButton(icon: Icons.bolt_rounded, label: 'TURBO', active: _turbo, onPressed: () => setState(() => _turbo = !_turbo)),
              const SizedBox(width: 10),
              Expanded(child: _spinButton()),
              const SizedBox(width: 10),
              DockToggleButton(
                icon: Icons.autorenew_rounded,
                label: 'AUTO',
                active: _auto,
                onPressed: () {
                  setState(() => _auto = !_auto);
                  if (_auto && !_spinning && _phase != SlotsPhase.bigWin) _spin();
                },
              ),
            ]),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('3 reels | 1 payline | RTP ${(cfg.rtp * 100).round()}%', style: AppText.body(12, weight: FontWeight.w600, color: AppColors.textDim)),
              PillButton(label: 'Paytable', icon: Icons.format_list_bulleted_rounded, height: 44, onPressed: () => _showPaytable(cfg)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _spinButton() {
    if (_spinning) {
      return AppButton(
        label: 'STOP',
        sublabel: 'SKIP ANIMATION',
        variant: AppButtonVariant.gold,
        height: 68,
        fontSize: 22,
        onPressed: () => setState(() => _skip = true),
      );
    }
    if (_cantAfford) {
      return AppButton(
        label: 'SPIN',
        sublabel: 'NOT ENOUGH CREDITS',
        variant: AppButtonVariant.ghost,
        height: 68,
        fontSize: 22,
        onPressed: _showNoCredits,
      );
    }
    return AppButton(
      label: 'SPIN',
      sublabel: 'BET ${fmt(_bet)}',
      variant: AppButtonVariant.success,
      height: 68,
      fontSize: 22,
      onPressed: _spin,
    );
  }

  // Big win
  Widget _bigWin() {
    final res = _last!;
    final sym = res.columns.map((c) => c[1]).toList();
    return ColoredBox(
      color: const Color(0xE605070A),
      child: BigWinOverlay(
        title: 'BIG WIN',
        amount: res.payout,
        multiplier: res.multiplier.toDouble(),
        multiplierDecimals: 0,
        caption: '3x ${symbolNames[sym[0]]} on a ${fmt(_bet)} bet',
        buttonLabel: 'CONTINUE',
        onCollect: _dismissBigWin,
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Container(
                width: 84,
                height: 84,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F3EE),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(color: kGold, spreadRadius: 3),
                    BoxShadow(color: Color(0xB3FFC83D), blurRadius: 26),
                  ],
                ),
                child: SymbolView(sym[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
