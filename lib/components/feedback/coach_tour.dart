import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../buttons/app_button.dart';
import '../core/app_colors.dart';
import '../core/app_haptics.dart';
import '../core/app_text.dart';
import '../core/app_tokens.dart';

/// Marks a widget so a [CoachTour] step can point at it.
///
/// ```dart
/// CoachTarget(id: 'balance', child: BalancePill(...))
/// ```
class CoachTarget extends StatelessWidget {
  const CoachTarget({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  static final Map<String, GlobalKey> _keys = {};

  static GlobalKey keyFor(String id) => _keys.putIfAbsent(id, () => GlobalKey(debugLabel: 'coach:$id'));

  /// Where the target is on screen right now, or null when it is not visible.
  static Rect? rectOf(String id) {
    final ctx = _keys[id]?.currentContext;
    final box = ctx?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize || box.size.isEmpty) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(key: keyFor(id), child: child);
}

/// One stop of a tour: a highlighted widget and a short note beside it.
class CoachStep {
  const CoachStep({required this.targetId, required this.title, required this.message, this.radius = 18, this.padding = 6});

  final String targetId;
  final String title;
  final String message;

  /// Corner radius of the highlight.
  final double radius;
  final double padding;
}

/// A guided walk-through: the screen dims, one widget is lit up and a small card floats next to it.
/// Not a dialog, so the screen stays visible and nothing is pushed on the navigator.
class CoachTour {
  CoachTour._();

  static NavigatorState? _nav;
  static Route<void>? _route;

  static bool get isShowing => _route != null;

  /// Steps whose target is not on screen are skipped. [onFinished] runs when the tour ends either way:
  /// finished, skipped, or closed with the Android back button.
  ///
  /// The tour is a see-through route on the root navigator, so system back closes it like any screen.
  static void show(BuildContext context, List<CoachStep> steps, {VoidCallback? onFinished}) {
    if (_route != null) return;
    final live = steps.where((s) => CoachTarget.rectOf(s.targetId) != null).toList();
    if (live.isEmpty) {
      onFinished?.call();
      return;
    }
    final nav = Navigator.of(context, rootNavigator: true);
    final route = PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, __, ___) => _TourOverlay(steps: live, onClose: dismiss),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    );
    _nav = nav;
    _route = route;
    nav.push<void>(route).then((_) {
      _route = null;
      _nav = null;
      onFinished?.call();
    });
  }

  static void dismiss() {
    final route = _route;
    final nav = _nav;
    if (route == null || nav == null) return;
    if (route.isActive) nav.pop();
  }
}

class _TourOverlay extends StatefulWidget {
  const _TourOverlay({required this.steps, required this.onClose});

  final List<CoachStep> steps;
  final VoidCallback onClose;

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> with TickerProviderStateMixin {
  late final AnimationController _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 320))..forward();

  int _i = 0;
  Rect _from = Rect.zero;
  Rect _to = Rect.zero;

  CoachStep get _step => widget.steps[_i];

  @override
  void initState() {
    super.initState();
    _to = _target();
    _from = _to;
  }

  @override
  void dispose() {
    _move.dispose();
    _pulse.dispose();
    _in.dispose();
    super.dispose();
  }

  Rect _target() => (CoachTarget.rectOf(_step.targetId) ?? _to).inflate(_step.padding);

  void _go(int next) {
    if (next >= widget.steps.length) {
      widget.onClose();
      return;
    }
    AppHaptics.light();
    final current = Rect.lerp(_from, _to, Curves.easeOutCubic.transform(_move.value)) ?? _to;
    setState(() {
      _i = next;
      _from = current;
      _to = _target();
    });
    _move.forward(from: 0);
    _in.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final last = _i == widget.steps.length - 1;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Swallows taps so the screen underneath can't be used mid-tour.
          Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {})),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: Listenable.merge([_move, _pulse, _in]),
                builder: (_, __) {
                  final rect = Rect.lerp(_from, _to, Curves.easeOutCubic.transform(_move.value)) ?? _to;
                  return CustomPaint(
                    painter: _SpotlightPainter(
                      rect: rect,
                      radius: _step.radius,
                      pulse: _pulse.value,
                      fade: _in.value,
                    ),
                  );
                },
              ),
            ),
          ),
          AnimatedBuilder(
            animation: Listenable.merge([_move, _in]),
            builder: (_, __) {
              final rect = Rect.lerp(_from, _to, Curves.easeOutCubic.transform(_move.value)) ?? _to;
              return _card(context, size, rect, last);
            },
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, Size size, Rect rect, bool last) {
    final pad = MediaQuery.paddingOf(context);
    final width = math.min(size.width - 32, 340.0);
    final left = (rect.center.dx - width / 2).clamp(16.0, size.width - width - 16).toDouble();
    final below = rect.center.dy < size.height * .55;
    final t = Curves.easeOutCubic.transform(_in.value);
    final shift = (below ? 10 : -10) * (1 - t);
    final arrowX = (rect.center.dx - left - 8).clamp(22.0, width - 38).toDouble();

    final card = Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.lineStrong),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_step.title, style: AppText.body(18, weight: FontWeight.w800, height: 1.2)),
          const SizedBox(height: 6),
          Text(_step.message, style: AppText.body(14, color: AppColors.textMuted, height: 1.45)),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var d = 0; d < widget.steps.length; d++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 5),
                  width: d == _i ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(color: d == _i ? AppColors.text : AppColors.handle, borderRadius: BorderRadius.circular(3)),
                ),
              const Spacer(),
              if (!last)
                AppButton(
                  label: 'Skip',
                  variant: AppButtonVariant.ghost,
                  expanded: false,
                  height: 40,
                  fontSize: 13,
                  letterSpacing: 0,
                  onPressed: widget.onClose,
                ),
              const SizedBox(width: 4),
              AppButton(
                label: last ? 'Got it' : 'Next',
                expanded: false,
                height: 40,
                fontSize: 13,
                letterSpacing: 0,
                onPressed: () => _go(_i + 1),
              ),
            ],
          ),
        ],
      ),
    );

    final arrow = Padding(
      padding: EdgeInsets.only(left: arrowX),
      child: Transform.rotate(
        angle: math.pi / 4,
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            border: Border(
              left: below ? BorderSide(color: AppColors.lineStrong) : BorderSide.none,
              top: below ? BorderSide(color: AppColors.lineStrong) : BorderSide.none,
              right: below ? BorderSide.none : BorderSide(color: AppColors.lineStrong),
              bottom: below ? BorderSide.none : BorderSide(color: AppColors.lineStrong),
            ),
          ),
        ),
      ),
    );

    final body = Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, shift),
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: below ? [Transform.translate(offset: const Offset(0, 8), child: arrow), card] : [card, Transform.translate(offset: const Offset(0, -8), child: arrow)],
          ),
        ),
      ),
    );

    return below
        ? Positioned(left: left, top: math.min(rect.bottom + 8, size.height - pad.bottom - 200), child: body)
        : Positioned(left: left, bottom: math.max(size.height - rect.top + 8, pad.bottom + 16), child: body);
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.rect, required this.radius, required this.pulse, required this.fade});

  final Rect rect;
  final double radius;
  final double pulse;
  final double fade;

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(hole)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(scrim, Paint()..color = Colors.black.withValues(alpha: .78 * fade));

    // Steady ring plus one soft ring that grows out and fades: points at the target without distracting.
    canvas.drawRRect(hole, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.white.withValues(alpha: .85 * fade));
    final grow = Curves.easeOut.transform(pulse) * 10;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(grow), Radius.circular(radius + grow)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: (1 - pulse) * .35 * fade),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.rect != rect || old.pulse != pulse || old.fade != fade || old.radius != radius;
}
