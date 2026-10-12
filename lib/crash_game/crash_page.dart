import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Provides CrashCharacter and CrashState (Idle, Run, Dead) from your character file.
import 'crash.dart';

/// Open it with:
/// Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CrashPage()));

const _bg = Color(0xFF0B0F14);
const _panel = Color(0xFF131A22);
const _gold = Color(0xFFFFC83D);
const _green = Color(0xFF2EE59D);
const _red = Color(0xFFFF4D4F);

String _money(double v) {
  final parts = v.toStringAsFixed(2).split('.');
  final whole = parts[0]
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '$whole.${parts[1]}';
}

// ───────────────────────── "Server" side ─────────────────────────
//
// Everything that decides the outcome lives here. The page never sees the
// crash point in advance: it only receives ticks, a cash-out confirmation and
// a crash event. To go live, implement the same three things (startRound
// stream, cashOut, balance) against your Edge Function / realtime channel and
// delete this class. The page code does not change.

enum RoundEventType { tick, cashedOut, crashed }

class RoundEvent {
  const RoundEvent._(this.type, this.multiplier, this.balance, this.payout);

  factory RoundEvent.tick(double multiplier, double balance) =>
      RoundEvent._(RoundEventType.tick, multiplier, balance, 0);

  factory RoundEvent.cashedOut(
          double multiplier, double payout, double balance) =>
      RoundEvent._(RoundEventType.cashedOut, multiplier, balance, payout);

  factory RoundEvent.crashed(double crashPoint, double balance) =>
      RoundEvent._(RoundEventType.crashed, crashPoint, balance, 0);

  final RoundEventType type;
  final double multiplier;
  final double balance;
  final double payout;
}

class MockCrashServer {
  MockCrashServer({
    this.balance = 100000.0,
    this.houseEdge = 0.03,
    this.growthRate = 0.12,
    this.maxCrash = 5000.0,
  });

  /// Virtual credits only.
  double balance;
  final double houseEdge;
  final double growthRate;
  final double maxCrash;

  final Random _rng = Random();
  final Stopwatch _clock = Stopwatch();
  StreamController<RoundEvent>? _ctrl;
  Timer? _timer;
  double _crashPoint = 1.0;
  double _bet = 0;
  double? _autoCashout;
  bool _cashedOut = false;

  double _multiplierNow() =>
      exp(growthRate * (_clock.elapsedMicroseconds / 1000000));

  double _drawCrashPoint() {
    final r = _rng.nextDouble();
    final raw = (100 * (1 - houseEdge) / (1 - r)).floorToDouble() / 100;
    return raw.clamp(1.0, maxCrash).toDouble();
  }

  Stream<RoundEvent> startRound({required double bet, double? autoCashout}) {
    _timer?.cancel();
    _ctrl?.close();

    balance -= bet;
    _bet = bet;
    _autoCashout =
        autoCashout == null ? null : (autoCashout * 100).round() / 100;
    _cashedOut = false;
    _crashPoint = _drawCrashPoint();

    final ctrl = StreamController<RoundEvent>();
    _ctrl = ctrl;
    _clock
      ..reset()
      ..start();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
    return ctrl.stream;
  }

  void _tick() {
    final ctrl = _ctrl;
    if (ctrl == null || ctrl.isClosed) return;

    final m = _multiplierNow();

    if (m >= _crashPoint) {
      _timer?.cancel();
      ctrl.add(RoundEvent.crashed(_crashPoint, balance));
      ctrl.close();
      _ctrl = null;
      return;
    }

    final auto = _autoCashout;
    if (!_cashedOut && auto != null && m >= auto) {
      _settleCashout(auto);
    }
    ctrl.add(RoundEvent.tick(m, balance));
  }

  void _settleCashout(double at) {
    _cashedOut = true;
    final payout = _bet * at;
    balance += payout;
    _ctrl?.add(RoundEvent.cashedOut(at, payout, balance));
  }

  /// The server clock is the truth: too late means the round already crashed.
  bool cashOut() {
    if (_ctrl == null || _cashedOut) return false;
    final m = _multiplierNow();
    if (m >= _crashPoint) return false;
    _settleCashout((m * 100).floorToDouble() / 100);
    return true;
  }

  void dispose() {
    _timer?.cancel();
    _ctrl?.close();
  }
}

// ───────────────────────── Page ─────────────────────────

enum RoundPhase { betting, running, crashed }

class CrashPage extends StatefulWidget {
  const CrashPage({super.key});

  @override
  State<CrashPage> createState() => _CrashPageState();
}

class _CrashPageState extends State<CrashPage>
    with SingleTickerProviderStateMixin {
  static const double _minBet = 10;
  static const double _maxBet = 500000;
  static const double _startCredits = 10000;

  final MockCrashServer _server = MockCrashServer(balance: _startCredits);
  StreamSubscription<RoundEvent>? _sub;
  Timer? _nextRound;
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  RoundPhase _phase = RoundPhase.betting;
  late double _balance = _server.balance;
  double _bet = 100;
  double _multiplier = 1.0;
  double? _cashedAt;
  double _payout = 0;
  bool _autoBet = false;
  bool _autoCashout = false;
  double _autoTarget = 2.0;

  // Demo seed so the history strip isn't empty when the page first opens.
  final List<double> _history = [
    1.87, 3.42, 1.12, 8.90, 2.05, 1.50, 12.30, 1.01, 4.60,
  ];

  @override
  void dispose() {
    _sub?.cancel();
    _nextRound?.cancel();
    _server.dispose();
    _shake.dispose();
    super.dispose();
  }

  // ───────── actions ─────────

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _setBet(double v) {
    final cap = max(_minBet, min(_maxBet, _balance));
    setState(() => _bet = v.clamp(_minBet, cap).toDouble());
  }

  void _setTarget(double v) {
    final c = v.clamp(1.1, 100.0).toDouble();
    setState(() => _autoTarget = (c * 100).round() / 100);
  }

  void _resetCredits() {
    _server.balance = _startCredits;
    setState(() => _balance = _server.balance);
  }

  void _startRound() {
    if (_phase == RoundPhase.running) return;
    if (_bet > _balance) {
      setState(() => _autoBet = false);
      _toast('Not enough demo credits');
      return;
    }
    _nextRound?.cancel();
    _sub?.cancel();

    final stream = _server.startRound(
      bet: _bet,
      autoCashout: _autoCashout ? _autoTarget : null,
    );
    _sub = stream.listen(_onEvent);

    setState(() {
      _phase = RoundPhase.running;
      _multiplier = 1.0;
      _cashedAt = null;
      _payout = 0;
      _balance = _server.balance;
    });
  }

  void _cashOut() {
    _server.cashOut(); // the result arrives as a cashedOut event
  }

  void _onEvent(RoundEvent e) {
    if (!mounted) return;
    setState(() {
      _balance = e.balance;
      switch (e.type) {
        case RoundEventType.tick:
          _multiplier = e.multiplier;
          break;
        case RoundEventType.cashedOut:
          _cashedAt = e.multiplier;
          _payout = e.payout;
          break;
        case RoundEventType.crashed:
          _multiplier = e.multiplier;
          _phase = RoundPhase.crashed;
          _history.insert(0, e.multiplier);
          if (_history.length > 20) _history.removeLast();
          // Keep the bet within what the wallet can afford.
          final cap = max(_minBet, min(_maxBet, e.balance));
          _bet = _bet.clamp(_minBet, cap).toDouble();
          break;
      }
    });

    if (e.type == RoundEventType.cashedOut) {
      HapticFeedback.mediumImpact();
    } else if (e.type == RoundEventType.crashed) {
      HapticFeedback.heavyImpact();
      _shake.forward(from: 0);
      _nextRound = Timer(const Duration(milliseconds: 2400), _backToBetting);
    }
  }

  void _backToBetting() {
    if (!mounted) return;
    setState(() {
      _phase = RoundPhase.betting;
      _multiplier = 1.0;
      _cashedAt = null;
      _payout = 0;
    });
    if (_autoBet) _startRound();
  }

  // ───────── derived ─────────

  CrashState get _charState {
    if (_phase == RoundPhase.running) return CrashState.Run;
    if (_phase == RoundPhase.crashed) return CrashState.Dead;
    return CrashState.Idle;
  }

  String get _status {
    if (_phase == RoundPhase.betting) return 'Place your bet to start the round';
    final cashed = _cashedAt;
    if (_phase == RoundPhase.running) {
      return cashed == null
          ? 'Cash out before it crashes!'
          : 'Cashed out at ${cashed.toStringAsFixed(2)}x  •  Payout ${_money(_payout)}';
    }
    return cashed == null
        ? 'Crashed. Bet lost.'
        : 'You cashed out at ${cashed.toStringAsFixed(2)}x  •  Payout ${_money(_payout)}';
  }

  // ───────── UI ─────────

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(useMaterial3: true)
          .copyWith(scaffoldBackgroundColor: _bg),
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _topBar(),
              const SizedBox(height: 4),
              _historyStrip(),
              Expanded(child: _stage()),
              _controlPanel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const Text(
            'CRASH',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              fontSize: 18,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _gold.withAlpha(120)),
            ),
            child: Row(
              children: [
                const Text(
                  'DEMO',
                  style: TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _money(_balance),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Reset demo credits',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _phase == RoundPhase.running ? null : _resetCredits,
          ),
        ],
      ),
    );
  }

  Widget _historyStrip() {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _history.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final v = _history[i];
          final c = v < 2 ? _red : (v < 10 ? _green : _gold);
          return Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: c.withAlpha(35),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: c.withAlpha(140)),
            ),
            child: Text(
              '${v.toStringAsFixed(2)}x',
              style: TextStyle(
                color: c,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _stage() {
    final crashed = _phase == RoundPhase.crashed;
    final cashed = _cashedAt != null;
    final accent = crashed ? _red : (cashed ? _green : _gold);
    final multColor = crashed ? _red : (cashed ? _green : Colors.white);

    return LayoutBuilder(
      builder: (context, box) {
        final charHeight = min(300.0, box.maxHeight * 0.62);
        return AnimatedBuilder(
          animation: _shake,
          builder: (context, child) {
            final t = _shake.value;
            final dx = (t == 0 || t == 1) ? 0.0 : sin(t * 60) * 12 * (1 - t);
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // Glow behind the character.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, 0.5),
                      radius: 0.9,
                      colors: [accent.withAlpha(80), Colors.transparent],
                    ),
                  ),
                ),
              ),
              // Ground ring.
              Positioned(
                bottom: 10,
                child: Container(
                  width: 240,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(120),
                    border: Border.all(color: accent.withAlpha(160), width: 2),
                    boxShadow: [
                      BoxShadow(color: accent.withAlpha(90), blurRadius: 24),
                    ],
                  ),
                ),
              ),
              // Character: Idle while betting, Run while climbing, Dead on crash.
              Positioned(
                bottom: 22,
                child: CrashCharacter(state: _charState, height: charHeight),
              ),
              // Multiplier + status.
              Positioned(
                top: 6,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${_multiplier.toStringAsFixed(2)}x',
                        style: TextStyle(
                          fontSize: 76,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          color: multColor,
                          shadows: [
                            Shadow(
                              color: multColor.withAlpha(120),
                              blurRadius: 24,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _controlPanel() {
    final locked = _phase == RoundPhase.running;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: const BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _betRow(locked),
          const SizedBox(height: 10),
          _quickRow(locked),
          const SizedBox(height: 8),
          _autoRow(locked),
          const SizedBox(height: 12),
          _mainButton(),
        ],
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback? onTap) {
    return SizedBox(
      width: 52,
      height: 52,
      child: FilledButton.tonal(
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onTap,
        child: Icon(icon),
      ),
    );
  }

  Widget _betRow(bool locked) {
    return Row(
      children: [
        _roundBtn(Icons.remove, locked ? null : () => _setBet(_bet - 10)),
        Expanded(
          child: Container(
            height: 56,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'BET',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 2,
                    color: Colors.white54,
                  ),
                ),
                Text(
                  _money(_bet),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
        _roundBtn(Icons.add, locked ? null : () => _setBet(_bet + 10)),
      ],
    );
  }

  Widget _quickRow(bool locked) {
    Widget chip(String label, double Function() value) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 34),
              side: const BorderSide(color: Colors.white24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: locked ? null : () => _setBet(value()),
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('Min', () => _minBet),
        chip('½', () => _bet / 2),
        chip('2×', () => _bet * 2),
        chip('Max', () => _maxBet),
      ],
    );
  }

  Widget _miniBtn(IconData icon, VoidCallback? onTap) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      iconSize: 20,
      icon: Icon(icon),
      onPressed: onTap,
    );
  }

  Widget _autoRow(bool locked) {
    final canEditTarget = !locked && _autoCashout;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilterChip(
          label: const Text('Auto bet'),
          selected: _autoBet,
          onSelected: (v) => setState(() => _autoBet = v),
        ),
        FilterChip(
          label: const Text('Auto cash-out'),
          selected: _autoCashout,
          onSelected: locked ? null : (v) => setState(() => _autoCashout = v),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _miniBtn(
              Icons.remove,
              canEditTarget ? () => _setTarget(_autoTarget - 0.1) : null,
            ),
            SizedBox(
              width: 58,
              child: Text(
                '${_autoTarget.toStringAsFixed(2)}x',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _autoCashout ? _gold : Colors.white38,
                ),
              ),
            ),
            _miniBtn(
              Icons.add,
              canEditTarget ? () => _setTarget(_autoTarget + 0.1) : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _mainButton() {
    final running = _phase == RoundPhase.running;
    String label;
    Color bg;
    VoidCallback? onTap;

    if (running && _cashedAt == null) {
      final live = (_multiplier * 100).floorToDouble() / 100;
      label = 'CASH OUT  ${_money(_bet * live)}';
      bg = _gold;
      onTap = _cashOut;
    } else if (running) {
      label = 'CASHED OUT';
      bg = _gold;
      onTap = null;
    } else {
      label = 'BET  ${_money(_bet)}';
      bg = _green;
      onTap = _startRound;
    }

    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: Colors.black,
        disabledBackgroundColor: Colors.white12,
        disabledForegroundColor: Colors.white54,
        minimumSize: const Size.fromHeight(60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onPressed: onTap,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
    );
  }
}