// Golden Reels: 3 reels, 1 payline.
//
// Server-driven: the page only talks to [SlotsServer] (the game server). The
// balance shown is the one Firestore wallet balance, held steady while the
// reels spin so it never jumps before the result.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import '../components/components.dart';
import '../core/api/api_client.dart';
import '../games/game_support.dart';
import '../model/model.dart';
import '../pages/paytable_page.dart';
import '../pages/round_format.dart';
import '../user/bloc/profile_cubit.dart';
import '../user/data/user_repository.dart';
import 'api_slots_server.dart';
import 'reel_widget.dart';
import 'slots_models.dart';
import 'slots_painters.dart';
import 'slots_server.dart';
import 'slots_theme.dart';
import 'slots_widgets.dart';
import 'symbol_view.dart';

enum SlotsPhase { idle, spinning, win, bigWin }

class SlotsPage extends StatefulWidget {
  const SlotsPage({super.key, this.info});

  /// Catalog entry (names, limits). Optional.
  final GameInfo? info;

  @override
  State<SlotsPage> createState() => _SlotsPageState();
}

class _SlotsPageState extends State<SlotsPage> with TickerProviderStateMixin, GameSessionMixin<SlotsPage> {
  late final SlotsServer _server = ApiSlotsServer(context.read<ApiClient>());
  SlotsConfig? _cfg;

  final _reelKeys = List.generate(3, (_) => GlobalKey<ReelWidgetState>());
  final _initial = const [
    [SlotSymbol.diamond, SlotSymbol.seven, SlotSymbol.bar],
    [SlotSymbol.bell, SlotSymbol.bar, SlotSymbol.cherry],
    [SlotSymbol.cherry, SlotSymbol.bell, SlotSymbol.diamond],
  ];

  SlotsPhase _phase = SlotsPhase.idle;
  bool _sheetOpen = false, _turbo = false, _auto = false, _skip = false;
  double _bet = 100, _win = 0;
  String _plate = 'Match 3 on the line to win';
  SpinResult? _last;
  final List<int> _history = [];
  List<SlotSymbol> _payline = [SlotSymbol.seven, SlotSymbol.bar, SlotSymbol.bell];

  late final AnimationController _fx = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  late final AnimationController _count = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState(); // GameSessionMixin: joins the session, starts music
    _turbo = context.read<ProfileCubit>().state.settings.turboByDefault;
    _load();
  }

  bool _loadFailed = false;

  void _load() {
    if (_loadFailed) setState(() => _loadFailed = false);
    _server.fetchConfig().then((c) {
      if (!mounted) return;
      setState(() {
        _cfg = c;
        _bet = c.defaultBet.clamp(c.minBet, maxBetFor(c.maxBet)).toDouble();
      });
      _loadHistory();
    }).catchError((Object _) {
      if (mounted) setState(() => _loadFailed = true);
    });
  }

  /// Last results from the player's own history, so the strip is real.
  Future<void> _loadHistory() async {
    try {
      final uid = profile.state.user.id;
      final rounds = await context.read<UserRepository>().watchRounds(uid, game: GameType.slots, limit: 12).first.timeout(const Duration(seconds: 4));
      if (!mounted || _history.isNotEmpty) return;
      setState(() => _history.addAll([for (final r in rounds.take(12)) r.returned.round()]));
    } catch (_) {}
  }

  @override
  void dispose() {
    _fx.dispose();
    _count.dispose();
    super.dispose();
  }

  bool get _isWinLike => _phase == SlotsPhase.win || _phase == SlotsPhase.bigWin;
  bool get _spinning => _phase == SlotsPhase.spinning;

  /// The real wallet balance. The header shows the same number (held while spinning).
  double get _balance => walletBalance;
  bool get _cantAfford => _balance < _bet;

  // ------ Bet controls ------
  void _setBet(double v) {
    if (_spinning || _cfg == null) return;
    setState(() => _bet = v.clamp(_cfg!.minBet, maxBetFor(_cfg!.maxBet)).roundToDouble());
  }

  void _step(int dir) {
    final steps = [for (final b in _cfg!.betSteps) if (b <= maxBetFor(_cfg!.maxBet)) b];
    if (steps.isEmpty) return;
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
    if (!checkCanPlay()) {
      _auto = false;
      return;
    }
    if (_cantAfford) {
      _showNoCredits();
      return;
    }
    AppHaptics.light();
    AppSound.play(Sfx.spin);
    holdBalance(_balance - _bet); // header shows the bet leaving at once
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
    } catch (e) {
      if (!mounted) return;
      for (var i = 0; i < 3; i++) {
        _reelKeys[i].currentState?.stopTo([SlotSymbol.cherry, _payline[i], SlotSymbol.bar], fast: true);
      }
      releaseBalance();
      _auto = false;
      AppSound.play(Sfx.error);
      setState(() {
        _phase = SlotsPhase.idle;
        _plate = failKind(e) == FailKind.network ? 'No connection. Try again' : 'Something went wrong. Try again';
      });
      if (failKind(e) == FailKind.noCredits) {
        _showNoCredits();
      } else {
        showToast(context, failText(e), error: true);
      }
      return;
    }
    if (!mounted) return;

    final minSpin = Duration(milliseconds: _turbo ? 350 : 900);
    final elapsed = DateTime.now().difference(started);
    if (!_skip && elapsed < minSpin) await Future<void>.delayed(minSpin - elapsed);
    if (!mounted) return;

    final gap = _turbo ? 60 : 160;
    final stops = <Future<void>>[];
    for (var i = 0; i < 3; i++) {
      stops.add(Future<void>.delayed(Duration(milliseconds: _skip ? 0 : gap * i), () {
        AppSound.play(Sfx.reelStop, volume: .7);
        return _reelKeys[i].currentState?.stopTo(res.columns[i], fast: _skip || _turbo);
      }));
    }
    await Future.wait(stops);
    if (!mounted) return;

    _last = res;
    _payline = [for (final c in res.columns) c[1]];
    _history.insert(0, res.multiplier);
    if (_history.length > 12) _history.removeLast();

    reportRound(bet: _bet, payout: res.payout);
    if (res.isWin) {
      final big = res.multiplier >= _cfg!.bigWinMultiplier;
      AppHaptics.medium();
      AppSound.play(big ? Sfx.bigWin : Sfx.win);
      holdBalance(res.balanceAfter); // the win lands in the header with the animation
      setState(() {
        _phase = big ? SlotsPhase.bigWin : SlotsPhase.win;
        _plate = res.label;
      });
      _count.forward(from: 0);
      if (big) {
        AppHaptics.heavy();
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
    _settle(res.balanceAfter);
    _afterRound();
  }

  /// Lets the header follow the live wallet again once Firestore shows the new
  /// balance (or after 3 seconds, whichever is first).
  Future<void> _settle(double expected) async {
    for (var i = 0; i < 30; i++) {
      if (!mounted) return;
      if ((walletBalance - expected).abs() < .005) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (mounted && !_spinning && _phase != SlotsPhase.bigWin) releaseBalance();
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
    releaseBalance();
    _afterRound();
  }

  // ------ Sheets and pages ------
  void _showFairness() => openFairness(context, roundId: _last?.roundId.isEmpty ?? true ? null : _last!.roundId);

  /// The paytable is a full page with a back button (not a sheet), so it is easy to leave.
  void _showPaytable(SlotsConfig cfg) {
    _sheetOpen = true;
    pushPage<void>(context, PaytablePage(cfg: cfg)).whenComplete(() => _sheetOpen = false);
  }

  Future<void> _showNoCredits() async {
    if (_sheetOpen) return;
    _sheetOpen = true;
    await showNoCredits(context, needed: _bet);
    _sheetOpen = false;
  }

  // ------ UI ------
  @override
  Widget build(BuildContext context) {
    final cfg = _cfg;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: cfg == null
          ? (_loadFailed
              ? SafeArea(child: Column(children: [SubPageBar(title: 'Slots', onBack: () => Navigator.maybePop(context)), Expanded(child: StatusView.offline(onRetry: _load))]))
              : const Center(child: CircularProgressIndicator(color: AppColors.gold)))
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
                            balance: watchBalance(context),
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
