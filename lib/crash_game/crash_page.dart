import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rev_game_mvp/components/components.dart';

import 'crash.dart';
import 'crash_server.dart';
import 'widgets/crash_panels.dart';
import 'widgets/crash_stage.dart';

/// Dash Crash.
///
/// Open it with:
/// Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CrashPage()));
///
/// The page only talks to [MockCrashServer] (see crash_server.dart). Swap that
/// class for your realtime / Edge Function client and this file does not change.
class CrashPage extends StatefulWidget {
  const CrashPage({super.key});

  @override
  State<CrashPage> createState() => _CrashPageState();
}

class _CrashPageState extends State<CrashPage> with SingleTickerProviderStateMixin {
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
  int _round = 4811;
  bool _autoBet = false;
  bool _autoCashout = false;
  double _autoTarget = 2.0;

  // Demo seed so the history strip isn't empty when the page first opens.
  final List<double> _history = [1.87, 3.42, 1.12, 8.90, 2.05, 1.50, 12.30, 1.01, 4.60];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheCrashFrames(context);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _nextRound?.cancel();
    _server.dispose();
    _shake.dispose();
    super.dispose();
  }

  // --------------------------- actions ---------------------------

  void _setBet(double v) {
    final cap = max(_minBet, min(_maxBet, _balance));
    setState(() => _bet = v.clamp(_minBet, cap).toDouble());
  }

  void _setTarget(double v) {
    final c = v.clamp(1.1, 100.0).toDouble();
    setState(() => _autoTarget = (c * 100).round() / 100);
  }

  void _getCredits() {
    _server.balance = _startCredits;
    setState(() => _balance = _server.balance);
  }

  void _startRound() {
    if (_phase == RoundPhase.running) return;
    if (_bet > _balance) {
      setState(() => _autoBet = false);
      _showNotEnough();
      return;
    }
    _nextRound?.cancel();
    _sub?.cancel();

    final stream = _server.startRound(
      bet: _bet,
      autoCashout: _autoCashout ? _autoTarget : null,
    );
    _sub = stream.listen(_onEvent);
    HapticFeedback.lightImpact();

    setState(() {
      _phase = RoundPhase.running;
      _round++;
      _multiplier = 1.0;
      _cashedAt = null;
      _payout = 0;
      _balance = _server.balance;
    });
  }

  void _cashOut() => _server.cashOut(); // the result arrives as a cashedOut event

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
      if (_autoBet) {
        _nextRound = Timer(const Duration(milliseconds: 2400), _backToBetting);
      }
    }
  }

  void _backToBetting() {
    _nextRound?.cancel();
    if (!mounted) return;
    setState(() {
      _phase = RoundPhase.betting;
      _multiplier = 1.0;
      _cashedAt = null;
      _payout = 0;
    });
    if (_autoBet) _startRound();
  }

  void _showVerify() {
    showAppBottomSheet<void>(
      context,
      title: 'Provably fair',
      child: const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: InfoCard(
          icon: Icons.verified_user_outlined,
          color: AppColors.green,
          message: 'The crash point is decided on the server before the round starts. '
              'Your device only plays the animation. Full seed checks arrive with the live server.',
        ),
      ),
    );
  }

  void _showNotEnough() {
    showAppBottomSheet<void>(
      context,
      child: Builder(builder: (sheetContext) {
        return Column(
          children: [
            Text('Not enough credits', style: AppText.body(22, weight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'You have ${formatCredits(_balance)} credits but this bet is ${formatCredits(_bet)}.',
              textAlign: TextAlign.center,
              style: AppText.body(14, color: AppColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 22),
            AppButton(
              label: 'Get demo credits',
              variant: AppButtonVariant.gold,
              onPressed: () {
                _getCredits();
                Navigator.pop(sheetContext);
              },
            ),
          ],
        );
      }),
    );
  }

  // --------------------------- UI ---------------------------

  @override
  Widget build(BuildContext context) {
    final running = _phase == RoundPhase.running;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: GlowBackground(
        glowColor: _phase == RoundPhase.crashed
            ? AppColors.lossStrong
            : (running ? AppColors.green : AppColors.purple),
        glowOpacity: .22,
        center: const Alignment(0, -.25),
        child: SafeArea(
          child: Column(
            children: [
              GameTopBar(
                title: 'Dash Crash',
                balance: _balance,
                low: _balance < _minBet,
                onBack: () => Navigator.of(context).maybePop(),
                onVerify: _showVerify,
              ),
              HistoryStrip(values: _history),
              const SizedBox(height: 12),
              Expanded(
                child: AnimatedBuilder(
                  animation: _shake,
                  builder: (context, child) {
                    final t = _shake.value;
                    final dx = (t == 0 || t == 1) ? 0.0 : sin(t * 60) * 10 * (1 - t);
                    return Transform.translate(offset: Offset(dx, 0), child: child);
                  },
                  child: CrashStage(
                    phase: _phase,
                    multiplier: _multiplier,
                    roundNumber: _round,
                    cashedAt: _cashedAt,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _panel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panel() {
    final Widget content;
    switch (_phase) {
      case RoundPhase.betting:
        content = CrashBetPanel(
          bet: _bet,
          minBet: _minBet,
          maxBet: min(_maxBet, max(_minBet, _balance)),
          onBetChanged: _setBet,
          autoCashout: _autoCashout,
          autoTarget: _autoTarget,
          onAutoCashoutChanged: (v) => setState(() => _autoCashout = v),
          onTargetChanged: _setTarget,
          autoBet: _autoBet,
          onAutoBetChanged: (v) => setState(() => _autoBet = v),
          onBet: _startRound,
        );
        break;
      case RoundPhase.running:
        content = CrashLivePanel(
          bet: _bet,
          multiplier: _multiplier,
          payout: _payout,
          cashedOut: _cashedAt != null,
          onCashOut: _cashOut,
          autoTarget: _autoCashout ? _autoTarget : null,
        );
        break;
      case RoundPhase.crashed:
        content = CrashResultPanel(
          bet: _bet,
          payout: _payout,
          cashedAt: _cashedAt,
          autoBet: _autoBet,
          onVerify: _showVerify,
          onNext: _backToBetting,
        );
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.sheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppColors.line)),
        boxShadow: [BoxShadow(color: Color(0x80000000), blurRadius: 32, offset: Offset(0, -8))],
      ),
      child: AnimatedSize(duration: const Duration(milliseconds: 180), alignment: Alignment.topCenter, child: content),
    );
  }
}
