import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'app_haptics.dart';
import 'app_sound.dart';

/// Wraps any widget with a tap and a snappy press animation: it dips the instant a finger lands and
/// springs back with a small overshoot when released. Pass `onTap: null` to disable.
///
/// A disabled control can still answer a tap: give it [onDisabledTap] and it wiggles and calls that
/// (use it to say why the control is off). A button that does nothing at all feels broken.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = 0.94,
    this.haptic = false,
    this.cooldown = Duration.zero,
    this.onDisabledTap,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;

  /// Taps that come sooner than this after the last accepted tap are ignored. Use it on buttons
  /// that start something (a bet, a payment, a save) so a double tap or a slow response can't run it twice.
  final Duration cooldown;

  /// Called when the control is disabled ([onTap] is null) and gets tapped.
  final VoidCallback? onDisabledTap;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> with SingleTickerProviderStateMixin {
  bool _down = false;
  DateTime? _lastTap;
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));

  bool get _enabled => widget.onTap != null;
  bool get _reactive => _enabled || widget.onDisabledTap != null;

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _set(bool v) {
    if (!_reactive || _down == v) return;
    setState(() => _down = v);
  }

  void _tap() {
    if (!_enabled) {
      AppHaptics.light();
      _shake.forward(from: 0);
      widget.onDisabledTap?.call();
      return;
    }
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
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _reactive ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapCancel: () => _set(false),
        onTapUp: (_) => _set(false),
        onTap: _reactive ? _tap : null,
        child: AnimatedBuilder(
          animation: _shake,
          builder: (context, child) {
            final t = _shake.value;
            final dx = t == 0 ? 0.0 : math.sin(t * math.pi * 5) * 5 * (1 - t);
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: AnimatedScale(
            scale: _down ? widget.scale : 1,
            // In fast, out with a little overshoot.
            duration: Duration(milliseconds: _down ? 60 : 220),
            curve: _down ? Curves.easeOut : Curves.easeOutBack,
            child: AnimatedOpacity(
              opacity: _down && _enabled ? .88 : 1,
              duration: const Duration(milliseconds: 60),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
