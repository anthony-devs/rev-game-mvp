import 'package:flutter/material.dart';
import 'app_haptics.dart';
import 'app_sound.dart';

/// Wraps any widget with a tap and a small press-down animation.
/// Pass `onTap: null` to disable.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = 0.97,
    this.haptic = false,
    this.cooldown = Duration.zero,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;

  /// Taps that come sooner than this after the last accepted tap are ignored. Use it on buttons
  /// that start something (a bet, a payment, a save) so a double tap or a slow response can't run it twice.
  final Duration cooldown;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;
  DateTime? _lastTap;

  void _set(bool v) {
    if (widget.onTap == null) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.cooldown > Duration.zero) {
                final now = DateTime.now();
                final last = _lastTap;
                if (last != null && now.difference(last) < widget.cooldown) return;
                _lastTap = now;
              }
              if (widget.haptic) {
                AppHaptics.light();
                AppSound.play(Sfx.tap, volume: .5);
              }
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 80),
        child: widget.child,
      ),
    ));
  }
}
