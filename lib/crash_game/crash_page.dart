import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rev_game_mvp/components/components.dart';

import '../core/api/api_client.dart';
import '../games/game_support.dart';
import '../model/model.dart';
import '../user/bloc/profile_cubit.dart';
import '../user/data/user_repository.dart';
import 'api_crash_server.dart';
import 'crash.dart';
import 'crash_server.dart';
import 'widgets/crash_panels.dart';
import 'widgets/crash_stage.dart';

/// Dash Crash. The page only talks to a [CrashServer] (the game server). The
/// balance in the header is the one Firestore balance, held while a round runs.
class CrashPage extends StatefulWidget {
  const CrashPage({super.key, this.info});

  /// Catalog entry (limits). Optional.
  final GameInfo? info;

  @override
  State<CrashPage> createState() => _CrashPageState();
}

class _CrashPageState extends State<CrashPage> with SingleTickerProviderStateMixin, GameSessionMixin<CrashPage> {
  static const double _minBet = 10;
  static const double _maxBetDefault = 500000;
  double get _maxBet => maxBetFor(widget.info?.maxBet ?? _maxBetDefault);

  late final CrashServer _server;
  StreamSubscription<RoundEvent>? _sub;
  Timer? _nextRound;
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  RoundPhase _phase = RoundPhase.betting;
  double get _balance => walletBalance;
  int _lastWhole = 1;
  double _bet = 100;
  double _multiplier = 1.0;
  double? _cashedAt;
  double _payout = 0;
  int _round = 4811;
  bool _autoBet = false;
  bool _autoCashout = false;
  double _autoTarget = 2.0;

  final List<double> _history = [];

  @override
  void initState() {
    super.initState();
    _server = ApiCrashServer(context.read<ApiClient>(), balance: walletBalance);
    _loadHistory();
  }

  /// Last crash points from the player's own history.
  Future<void> _loadHistory() async {
    try {
      final rounds = await context
          .read<UserRepository>()
          .watchRounds(profile.state.user.id, game: GameType.crash, limit: 20)
          .first
          .timeout(const Duration(seconds: 4));
      if (!mounted || _history.isNotEmpty) return;
      setState(() => _history.addAll([for (final r in rounds) r.multiplier]));
    } catch (_) {}
  }

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

  void _startRound() {
    if (_phase == RoundPhase.running) return;
    if (!checkCanPlay()) {
      setState(() => _autoBet = false);
      return;
    }
    if (_bet > _balance) {
      setState(() => _autoBet = false);
      showNoCredits(context, needed: _bet);
      return;
    }
    _nextRound?.cancel();
    holdBalance(_balance - _bet); // the bet leaves the header at once
    _sub?.cancel();

    final stream = _server.startRound(
      bet: _bet,
      autoCashout: _autoCashout ? _autoTarget : null,
    );
    _sub = stream.listen(_onEvent, onError: _onStreamError);
    AppHaptics.light();
    AppSound.play(Sfx.crashStart);
    _lastWhole = 1;

    setState(() {
      _phase = RoundPhase.running;
      _round++;
      _multiplier = 1.0;
      _cashedAt = null;
      _payout = 0;
    });
  }

  void _cashOut() => _server.cashOut(); // the result arrives as a cashedOut event

  /// The bet was not taken (no connection, not enough credits) or the stream broke.
  void _onStreamError(Object error) {
    if (!mounted) return;
    final started = _phase == RoundPhase.running;
    releaseBalance();
    setState(() {
      _phase = RoundPhase.betting;
      _autoBet = false;
      if (started) _round--;
    });
    AppSound.play(Sfx.error);
    if (failKind(error) == FailKind.noCredits) {
      showNoCredits(context, needed: _bet);
    } else {
      _showError(error);
    }
  }

  void _showError(Object error) => showToast(context, failText(error), error: true);

  void _onEvent(RoundEvent e) {
    if (!mounted) return;
    setState(() {
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

    if (e.type == RoundEventType.tick) {
      final whole = e.multiplier.floor();
      if (whole > _lastWhole && _cashedAt == null) {
        _lastWhole = whole;
        AppSound.play(Sfx.crashTick);
      }
    } else if (e.type == RoundEventType.cashedOut) {
      AppHaptics.medium();
      AppSound.play(Sfx.cashOut);
      holdBalance(e.balance);
      reportRound(bet: _bet, payout: e.payout);
      _settle(e.balance);
    } else if (e.type == RoundEventType.crashed) {
      AppHaptics.heavy();
      _shake.forward(from: 0);
      if (_cashedAt == null) {
        AppSound.play(Sfx.bust);
        holdBalance(e.balance);
        reportRound(bet: _bet, payout: 0);
        _settle(e.balance);
      }
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

  void _showVerify() => openFairness(context, roundId: _phase == RoundPhase.running ? null : _server.roundId);

  /// Header follows the live wallet again once Firestore shows the new balance.
  Future<void> _settle(double expected) async {
    for (var i = 0; i < 30; i++) {
      if (!mounted) return;
      if ((walletBalance - expected).abs() < .005) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (mounted && _phase != RoundPhase.running) releaseBalance();
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
                balance: watchBalance(context),
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
