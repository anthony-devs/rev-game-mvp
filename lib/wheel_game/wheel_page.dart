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
import 'wheel_api.dart';

const _tau = math.pi * 2;

String _x(double v) => v == 0 ? '0x' : '${v.toStringAsFixed(v < 10 && v != v.roundToDouble() ? 2 : 0)}x';

Color _tint(double m) {
  if (m <= 0) return AppColors.surfaceAlt;
  if (m < 1) return AppColors.blue;
  if (m < 2) return AppColors.green;
  if (m < 5) return AppColors.gold;
  return AppColors.purple;
}

/// Lucky Wheel. The server picks the segment, the wheel then shows it.
class WheelPage extends StatefulWidget {
  const WheelPage({super.key, this.info});

  final GameInfo? info;

  @override
  State<WheelPage> createState() => _WheelPageState();
}

class _WheelPageState extends State<WheelPage> with GameSessionMixin<WheelPage>, SingleTickerProviderStateMixin {
  @override
  GameType get guideType => GameType.wheel;

  static const _chips = <double>[10, 50, 100, 500, 1000];
  static const _risks = <String>['low', 'medium', 'high'];

  late final WheelApi _api;
  late final AnimationController _spin;
  Animation<double>? _anim;

  WheelConfig? _config;
  bool _loadFailed = false;
  double _bet = 100;
  String _risk = 'medium';
  double _rot = 0;
  WheelResult? _result;
  bool _busy = false;

  double get _minBet => widget.info?.minBet ?? 10;
  double get _maxBet => maxBetFor(widget.info?.maxBet ?? 2000);
  List<double> get _segments => _config?.segments[_risk] ?? const [];

  @override
  void initState() {
    super.initState();
    _api = WheelApi(context.read<ApiClient>());
    _bet = _bet.clamp(_minBet, _maxBet).toDouble();
    _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400))
      ..addListener(() {
        final a = _anim;
        if (a != null) setState(() => _rot = a.value);
      });
    _load();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
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
    });
    holdBalance(walletBalance - _bet);
    AppSound.play(Sfx.chip);
    AppHaptics.light();
    try {
      final r = await _api.spin(_bet, _risk);
      if (!mounted) return;
      final n = r.segments.length;
      final seg = _tau / n;
      final want = -(r.index + .5) * seg;
      var delta = (want - _rot) % _tau;
      if (delta < 0) delta += _tau;
      final target = _rot + _tau * 5 + delta;
      _anim = Tween<double>(begin: _rot, end: target).animate(CurvedAnimation(parent: _spin, curve: Curves.easeOutCubic));
      AppSound.play(Sfx.spin);
      await _spin.forward(from: 0);
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

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final balance = watchBalance(context);
    final r = _result;
    final tone = r == null ? AppColors.gold : (r.isWin ? AppColors.green : (r.isPush ? AppColors.gold : AppColors.loss));

    return GameScaffold(
      title: 'Lucky Wheel',
      balance: balance,
      lowBalance: walletBalance < _minBet && !_busy,
      glowColor: tone,
      onHelp: () => openGuide(context, GameType.wheel),
      onVerify: () => openFairness(context, roundId: r?.roundId),
      stage: _stage(r),
      panel: _panel(r, tone),
    );
  }

  Widget _stage(WheelResult? r) {
    if (_config == null) {
      return Center(
        child: _loadFailed
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Could not load the wheel.', style: AppText.body(14, color: AppColors.textMuted)),
                const SizedBox(height: 12),
                AppButton(label: 'Try again', variant: AppButtonVariant.outline, height: 44, fontSize: 14, onPressed: _load),
              ])
            : const AppLoader(),
      );
    }
    final landed = r != null && !_busy ? r.index : null;
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(child: CustomPaint(painter: _WheelPainter(segments: _segments, rotation: _rot, landed: landed))),
            Align(
              alignment: Alignment.topCenter,
              child: Transform.translate(offset: const Offset(0, -8), child: Icon(Icons.arrow_drop_down_rounded, size: 44, color: AppColors.text)),
            ),
            Container(
              width: 74,
              height: 74,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.sheet, border: Border.all(color: AppColors.line, width: 2)),
              child: Text(
                _busy ? '...' : (r == null ? 'SPIN' : _x(r.multiplier)),
                style: AppText.number(r == null || _busy ? 14 : 20, color: r == null ? AppColors.textMuted : _tint(r.multiplier == 0 ? 1 : r.multiplier)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _panel(WheelResult? r, Color tone) {
    final children = <Widget>[
      if (r != null && !_busy) ...[
        Row(children: [
          Expanded(
            child: Text(r.isWin ? 'YOU WON' : (r.isPush ? 'BET RETURNED' : 'NO WIN'), style: AppText.label(color: tone)),
          ),
          Text(formatSigned(r.net), style: AppText.number(26, color: tone, shadows: r.isWin ? AppText.glow(tone, opacity: .4) : null)),
        ]),
        const SizedBox(height: 12),
      ],
      Row(children: [
        for (var i = 0; i < _risks.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: PressScale(
              onTap: _busy ? null : () {
                AppSound.play(Sfx.tap);
                setState(() {
                  _risk = _risks[i];
                  _result = null;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 11),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _risk == _risks[i] ? AppColors.gold.withValues(alpha: .16) : AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _risk == _risks[i] ? AppColors.gold : AppColors.line, width: _risk == _risks[i] ? 1.6 : 1),
                ),
                child: Text(_risks[i].toUpperCase(), style: AppText.label(color: _risk == _risks[i] ? AppColors.gold : AppColors.textMuted, size: 11)),
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 12),
      BetChipPicker(values: _chips, selected: _bet, size: 50, onSelected: (v) {
        if (_busy) return;
        AppSound.play(Sfx.chip);
        setState(() => _bet = v.clamp(_minBet, _maxBet).toDouble());
      }),
      const SizedBox(height: 12),
      AppButton(
        label: r == null ? 'SPIN' : 'SPIN AGAIN',
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

class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.segments, required this.rotation, this.landed});

  final List<double> segments;
  final double rotation;
  final int? landed;

  @override
  void paint(Canvas canvas, Size size) {
    final n = segments.length;
    if (n == 0) return;
    final c = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2;
    final rect = Rect.fromCircle(center: c, radius: radius);
    final seg = _tau / n;
    // Segment 0 starts at the top and runs clockwise.
    final start0 = -math.pi / 2 + rotation;
    for (var i = 0; i < n; i++) {
      final a = start0 + i * seg;
      final m = segments[i];
      final lit = landed == null || landed == i;
      final base = _tint(m);
      canvas.drawArc(rect, a, seg, true, Paint()..color = m == 0 ? AppColors.surfaceAlt : base.withValues(alpha: lit ? .9 : .35));
      canvas.drawArc(rect, a, seg, true, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.bg);
      final mid = a + seg / 2;
      final tp = TextPainter(
        text: TextSpan(text: _x(m), style: AppText.number(radius * .068, color: m == 0 ? AppColors.textFaint : Colors.white)),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(c.dx + math.cos(mid) * radius * .82, c.dy + math.sin(mid) * radius * .82);
      canvas.rotate(mid + math.pi / 2);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
    canvas.drawCircle(c, radius, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = AppColors.line);
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.rotation != rotation || old.segments != segments || old.landed != landed;
}
