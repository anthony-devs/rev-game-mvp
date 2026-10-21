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
import 'arcade_api.dart';

String _x(double v) => v == 0 ? '0x' : '${v.toStringAsFixed(v < 10 && v != v.roundToDouble() ? 2 : 0)}x';

const _gem = <Color>[Color(0xFFE5484D), Color(0xFFF5A524), Color(0xFFFFD60A), Color(0xFF30D158), Color(0xFF32ADE6), Color(0xFF8E7CFF), Color(0xFFFF6BD6)];

/// Limbo, Coin Flip, Rock Paper Scissors, Darts, Scratch Card, Diamonds and Card War.
/// One screen for all of them: the server decides, this screen shows it.
class ArcadeInstantPage extends StatefulWidget {
  const ArcadeInstantPage({super.key, required this.info});

  final GameInfo info;

  @override
  State<ArcadeInstantPage> createState() => _ArcadeInstantPageState();
}

class _ArcadeInstantPageState extends State<ArcadeInstantPage> with GameSessionMixin<ArcadeInstantPage> {
  @override
  GameType get guideType => widget.info.type;

  static const _chips = <double>[10, 50, 100, 500, 1000];
  static const _targets = <double>[1.5, 2, 3, 5, 10, 50];

  String get _id => widget.info.id;

  late final ArcadeApi _api;
  ArcadeConfig? _config;
  bool _loadFailed = false;
  double _bet = 100;
  bool _busy = false;
  ArcadeResult? _result;
  ArcadeResult? _pending; // the answer while the show plays

  // What the player chose.
  double _target = 2;
  String _pick = '';
  String _risk = 'medium';

  // What the stage shows while a round plays out.
  int _shown = 0; // how many reveal steps are visible (gems, scratch tiles)
  bool _flipping = false;
  double _counter = 1;

  double get _minBet => widget.info.minBet;
  double get _maxBet => maxBetFor(widget.info.maxBet);

  @override
  void initState() {
    super.initState();
    _api = ArcadeApi(context.read<ApiClient>(), _id);
    _bet = _bet.clamp(_minBet, _maxBet).toDouble();
    _pick = {'coinflip': 'heads', 'rps': 'rock'}[_id] ?? '';
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadFailed = false);
    try {
      final c = await _api.config();
      if (!mounted) return;
      setState(() {
        _config = c;
        if (c.risks.isNotEmpty && !c.risks.contains(_risk)) _risk = c.risks.first;
      });
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

  Map<String, dynamic> get _choice {
    switch (_id) {
      case 'limbo':
        return {'target': _target};
      case 'coinflip':
      case 'rps':
        return {'pick': _pick};
      case 'darts':
        return {'risk': _risk};
    }
    return const {};
  }

  Future<void> _go() async {
    if (_busy || _config == null) return;
    if (!checkCanPlay()) return;
    if (_bet > walletBalance) {
      showNoCredits(context, needed: _bet);
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
      _pending = null;
      _shown = 0;
      _counter = 1;
    });
    holdBalance(walletBalance - _bet);
    AppSound.play(Sfx.chip);
    AppHaptics.light();
    try {
      final r = await _api.play(_bet, _choice);
      if (!mounted) return;
      setState(() => _pending = r);
      await _reveal(r);
      if (!mounted) return;
      setState(() {
        _result = r;
        _pending = null;
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
        _pending = null;
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

  /// The little show before the result is revealed.
  Future<void> _reveal(ArcadeResult r) async {
    switch (_id) {
      case 'limbo':
        final end = parseNum(r.detail['point']).toDouble();
        const steps = 22;
        for (var i = 1; i <= steps; i++) {
          if (!mounted) return;
          final t = Curves.easeOut.transform(i / steps);
          setState(() => _counter = 1 + (end - 1) * t);
          await Future<void>.delayed(const Duration(milliseconds: 45));
        }
        break;
      case 'darts':
        const frames = 18;
        setState(() => _counter = 0);
        AppSound.play(Sfx.spin);
        for (var i = 1; i <= frames; i++) {
          if (!mounted) return;
          setState(() => _counter = i / frames);
          await Future<void>.delayed(const Duration(milliseconds: 26));
        }
        AppSound.play(Sfx.reelStop);
        AppHaptics.light();
        await Future<void>.delayed(const Duration(milliseconds: 380));
        break;
      case 'coinflip':
        setState(() => _flipping = true);
        AppSound.play(Sfx.spin);
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (mounted) setState(() => _flipping = false);
        break;
      case 'diamonds':
        for (var i = 1; i <= 5; i++) {
          if (!mounted) return;
          setState(() => _shown = i);
          AppSound.play(Sfx.tap);
          await Future<void>.delayed(const Duration(milliseconds: 260));
        }
        break;
      case 'scratch':
        for (var i = 1; i <= 6; i++) {
          if (!mounted) return;
          setState(() => _shown = i);
          AppSound.play(Sfx.tap);
          await Future<void>.delayed(const Duration(milliseconds: 220));
        }
        break;
      case 'war':
        setState(() => _shown = 1);
        AppSound.play(Sfx.tap);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (mounted) setState(() => _shown = 2);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        break;
      default:
        AppSound.play(Sfx.spin);
        await Future<void>.delayed(const Duration(milliseconds: 650));
    }
  }

  num parseNum(Object? v) => v is num ? v : (num.tryParse('$v') ?? 1);

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final balance = watchBalance(context);
    final r = _result;
    final tone = r == null ? AppColors.gold : (r.isWin ? AppColors.green : (r.isPush ? AppColors.gold : AppColors.loss));
    return GameScaffold(
      title: widget.info.name,
      balance: balance,
      lowBalance: walletBalance < _minBet && !_busy,
      glowColor: tone,
      onHelp: () => openGuide(context, widget.info.type),
      onVerify: () => openFairness(context, roundId: r?.roundId),
      stage: _stage(_result ?? _pending, tone),
      panel: _panel(r, tone),
    );
  }

  Widget _stage(ArcadeResult? r, Color tone) {
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
    switch (_id) {
      case 'limbo':
        return _limbo(r, tone);
      case 'coinflip':
        return _coin(r, tone);
      case 'rps':
        return _rps(r, tone);
      case 'darts':
        return _darts(r);
      case 'scratch':
        return _scratch(r);
      case 'diamonds':
        return _diamonds(r);
      default:
        return _war(r);
    }
  }

  // ---- stages

  Widget _limbo(ArcadeResult? r, Color tone) {
    final chance = ((1 - _config!.edge) / _target * 100).clamp(0, 100).toDouble();
    final shown = r != null && !_busy ? parseNum(r.detail['point']).toDouble() : _counter;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${shown.toStringAsFixed(2)}x', style: AppText.number(64, color: r == null ? AppColors.text : tone)),
        const SizedBox(height: 6),
        Text(r == null || _busy ? 'TARGET ${_target.toStringAsFixed(2)}x' : (r.isWin ? 'REACHED YOUR TARGET' : 'MISSED THE TARGET'), style: AppText.label(color: AppColors.textMuted)),
        const SizedBox(height: 4),
        Text('${chance.toStringAsFixed(chance < 10 ? 2 : 1)}% chance to win', style: AppText.body(13, color: AppColors.textDim)),
      ]),
    );
  }

  Widget _coin(ArcadeResult? r, Color tone) {
    final side = r?.detail['side'] as String?;
    final face = _flipping || side == null ? '?' : (side == 'heads' ? 'H' : 'T');
    return Center(
      child: AnimatedRotation(
        turns: _flipping ? 4 : 0,
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        child: Container(
          width: 150,
          height: 150,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.gold.withValues(alpha: .18), border: Border.all(color: AppColors.gold, width: 4)),
          child: Text(face, style: AppText.number(64, color: AppColors.gold)),
        ),
      ),
    );
  }

  Widget _rps(ArcadeResult? r, Color tone) {
    const icons = {'rock': '✊', 'paper': '✋', 'scissors': '✌️'};
    final cpu = r?.detail['cpu'] as String?;
    Widget hand(String label, String? what) => Column(mainAxisSize: MainAxisSize.min, children: [
          Text(what == null ? '❔' : icons[what]!, style: const TextStyle(fontSize: 76)),
          const SizedBox(height: 6),
          Text(label, style: AppText.label(color: AppColors.textMuted)),
        ]);
    return Center(
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        hand('YOU', _pick),
        Text('VS', style: AppText.number(18, color: AppColors.textDim)),
        hand('HOUSE', _busy ? null : cpu),
      ]),
    );
  }

  Widget _darts(ArcadeResult? r) {
    final seg = _config!.segments(_risk);
    final target = r == null ? null : parseNum(r.detail['index']).toInt();
    final landed = target != null && !_busy ? target : null;
    final t = r == null ? 0.0 : (_busy ? _counter : 1.0);
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Padding(padding: const EdgeInsets.all(20), child: CustomPaint(painter: _BoardPainter(seg, landed, target, t))),
      ),
    );
  }

  Widget _scratch(ArcadeResult? r) {
    final prize = r == null ? 0.0 : parseNum(r.detail['prize']).toDouble();
    // Three matching tiles on a win, six different ones on a loss.
    final faces = prize > 0
        ? [_x(prize), '1x', _x(prize), '5x', _x(prize), '2x']
        : ['1x', '2x', '5x', '10x', '20x', '50x'];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < 6; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _shown > i ? AppColors.surface : AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _shown > i && prize > 0 && faces[i] == _x(prize) ? AppColors.gold : AppColors.line, width: 1.5),
                ),
                child: Text(_shown > i ? faces[i] : '?', style: AppText.number(22, color: _shown > i && prize > 0 && faces[i] == _x(prize) ? AppColors.gold : AppColors.textMuted)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _diamonds(ArcadeResult? r) {
    final colors = r == null ? <int>[] : [for (final c in (r.detail['colors'] as List)) parseNum(c).toInt()];
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: AnimatedScale(
                scale: _shown > i ? 1 : .6,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.diamond_rounded, size: 48, color: _shown > i && i < colors.length ? _gem[colors[i] % _gem.length] : AppColors.surfaceAlt),
              ),
            ),
        ]),
        const SizedBox(height: 22),
        if (_config != null)
          for (final p in _config!.pays)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('${_patternName(p.$1)}   ${_x(p.$2)}', style: AppText.body(12, color: AppColors.textDim)),
            ),
      ]),
    );
  }

  String _patternName(List<int> p) {
    switch (p.join(',')) {
      case '5':
        return 'Five of a kind';
      case '4,1':
        return 'Four of a kind';
      case '3,2':
        return 'Full house';
      case '3,1,1':
        return 'Three of a kind';
      default:
        return 'Two pairs';
    }
  }

  Widget _war(ArcadeResult? r) {
    String rank(int v) => const {11: 'J', 12: 'Q', 13: 'K', 14: 'A'}[v] ?? '$v';
    Widget card(String label, int? v, bool show) => Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 96,
            height: 136,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: show ? Colors.white : AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
            child: Text(show && v != null ? rank(v) : '?', style: AppText.number(44, color: show ? const Color(0xFF111111) : AppColors.textDim)),
          ),
          const SizedBox(height: 8),
          Text(label, style: AppText.label(color: AppColors.textMuted)),
        ]);
    final p = r == null ? null : parseNum(r.detail['player']).toInt();
    final d = r == null ? null : parseNum(r.detail['dealer']).toInt();
    return Center(
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        card('YOU', p, r != null && (_shown >= 1 || !_busy)),
        card('DEALER', d, r != null && (_shown >= 2 || !_busy)),
      ]),
    );
  }

  // ---- controls

  Widget _choiceRow(List<(String, String)> items, String selected, ValueChanged<String> onTap) {
    return Row(children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: PressScale(
            onTap: _busy
                ? null
                : () {
                    AppSound.play(Sfx.tap);
                    setState(() {
                      onTap(items[i].$1);
                      _result = null;
                    });
                  },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(vertical: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected == items[i].$1 ? AppColors.gold.withValues(alpha: .16) : AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: selected == items[i].$1 ? AppColors.gold : AppColors.line, width: selected == items[i].$1 ? 1.6 : 1),
              ),
              child: Text(items[i].$2, style: AppText.label(color: selected == items[i].$1 ? AppColors.gold : AppColors.textMuted, size: 11)),
            ),
          ),
        ),
      ],
    ]);
  }

  Widget _controls() {
    switch (_id) {
      case 'limbo':
        return _choiceRow([for (final t in _targets) (t.toString(), '${t % 1 == 0 ? t.toInt() : t}x')], _target.toString(), (v) => _target = double.parse(v));
      case 'coinflip':
        return _choiceRow(const [('heads', 'HEADS'), ('tails', 'TAILS')], _pick, (v) => _pick = v);
      case 'rps':
        return _choiceRow(const [('rock', '✊ ROCK'), ('paper', '✋ PAPER'), ('scissors', '✌️ SCISSORS')], _pick, (v) => _pick = v);
      case 'darts':
        return _choiceRow([for (final k in _config?.risks ?? const <String>[]) (k, k.toUpperCase())], _risk, (v) => _risk = v);
    }
    return const SizedBox.shrink();
  }

  String get _goLabel => const {'scratch': 'SCRATCH', 'war': 'DEAL', 'diamonds': 'DRAW', 'coinflip': 'FLIP', 'darts': 'THROW'}[_id] ?? 'PLAY';

  Widget _panel(ArcadeResult? r, Color tone) {
    final hasControls = const {'limbo', 'coinflip', 'rps', 'darts'}.contains(_id);
    final children = <Widget>[
      if (r != null && !_busy) ...[
        Row(children: [
          Expanded(child: Text(r.isWin ? 'YOU WON' : (r.isPush ? 'BET RETURNED' : 'NO WIN'), style: AppText.label(color: tone))),
          Text(formatSigned(r.net), style: AppText.number(26, color: tone, shadows: r.isWin ? AppText.glow(tone, opacity: .4) : null)),
        ]),
        const SizedBox(height: 4),
        Align(alignment: Alignment.centerLeft, child: Text(r.label, style: AppText.body(12, color: AppColors.textDim))),
        const SizedBox(height: 10),
      ],
      if (hasControls && _config != null) ...[_controls(), const SizedBox(height: 12)],
      BetChipPicker(values: _chips, selected: _bet, size: 50, onSelected: (v) {
        if (_busy) return;
        AppSound.play(Sfx.chip);
        setState(() => _bet = v.clamp(_minBet, _maxBet).toDouble());
      }),
      const SizedBox(height: 12),
      AppButton(
        label: r == null ? _goLabel : '$_goLabel AGAIN',
        sublabel: 'BET ${formatCredits(_bet, decimals: 0)}',
        variant: AppButtonVariant.success,
        height: 56,
        fontSize: 16,
        loading: _busy,
        onPressed: _busy || _config == null ? null : _go,
      ),
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

/// A dartboard of 20 segments; the one that was hit lights up.
class _BoardPainter extends CustomPainter {
  _BoardPainter(this.segments, this.landed, this.target, this.t);

  final List<double> segments;
  final int? landed;

  /// Segment the dart is flying to, and how far it has flown (0 to 1).
  final int? target;
  final double t;

  Color _tint(double m) {
    if (m <= 0) return AppColors.surfaceAlt;
    if (m < 2) return AppColors.green;
    if (m < 5) return AppColors.gold;
    return AppColors.purple;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = segments.length;
    if (n == 0) return;
    final c = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: c, radius: radius);
    final seg = math.pi * 2 / n;
    for (var i = 0; i < n; i++) {
      final a = -math.pi / 2 + i * seg;
      final lit = landed == null || landed == i;
      canvas.drawArc(rect, a, seg, true, Paint()..color = segments[i] == 0 ? AppColors.surfaceAlt : _tint(segments[i]).withValues(alpha: lit ? .9 : .3));
      canvas.drawArc(rect, a, seg, true, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.bg);
      final mid = a + seg / 2;
      final tp = TextPainter(
        text: TextSpan(text: _x(segments[i]), style: AppText.number(radius * .068, color: segments[i] == 0 ? AppColors.textFaint : Colors.white)),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(c.dx + math.cos(mid) * radius * .82, c.dy + math.sin(mid) * radius * .82);
      canvas.rotate(mid + math.pi / 2);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
    canvas.drawCircle(c, radius * .12, Paint()..color = AppColors.sheet);
    if (target != null && t > 0) {
      final mid = -math.pi / 2 + (target! + .5) * seg;
      final hit = c + Offset(math.cos(mid), math.sin(mid)) * radius * .62;
      final from = Offset(c.dx + radius * .15, c.dy + radius * 1.55);
      final k = Curves.easeIn.transform(t.clamp(0.0, 1.0));
      // The dart flies in on a slight arc and shrinks a little as it lands.
      final tip = Offset.lerp(from, hit, k)! + Offset(0, -math.sin(k * math.pi) * radius * .12);
      final dir = (hit - from) / (hit - from).distance;
      final len = radius * .3 * (1 - .15 * k);
      final tail = tip - dir * len;
      final perp = Offset(-dir.dy, dir.dx);
      final shaft = Paint()
        ..color = Colors.white
        ..strokeWidth = radius * .028
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(tail, tip, shaft);
      final wing = Paint()
        ..color = AppColors.loss
        ..strokeWidth = radius * .03
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(tail, tail - dir * radius * .06 + perp * radius * .07, wing);
      canvas.drawLine(tail, tail - dir * radius * .06 - perp * radius * .07, wing);
      canvas.drawCircle(tip, radius * .022, Paint()..color = AppColors.gold);
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => old.landed != landed || old.segments != segments || old.target != target || old.t != t;
}
