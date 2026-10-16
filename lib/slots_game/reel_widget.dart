import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'slots_models.dart';
import 'slots_theme.dart';
import 'symbol_view.dart';

const double _pitch = 66; // distance between symbol rows
const double _cellTop = -35; // y of the row above the payline when pos == 0

class ReelWidget extends StatefulWidget {
  const ReelWidget({super.key, required this.initial, required this.highlight});
  final List<SlotSymbol> initial; // [top, payline, bottom]
  final bool highlight;

  @override
  State<ReelWidget> createState() => ReelWidgetState();
}

class ReelWidgetState extends State<ReelWidget> with SingleTickerProviderStateMixin {
  final _rnd = math.Random();
  late List<SlotSymbol> _tape = List.of(widget.initial);
  double _pos = 0;
  bool _spinning = false;
  bool _stopping = false;
  double _blur = 0;

  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;
  double _from = 0, _to = 0;
  Duration _t0 = Duration.zero, _dur = Duration.zero;
  Completer<void>? _done;
  static const _curve = Cubic(0.2, 0.9, 0.3, 1.18); // eases out with a small bounce

  SlotSymbol _rand() => SlotSymbol.values[_rnd.nextInt(SlotSymbol.values.length)];

  SlotSymbol _at(int r) {
    if (r < 0) return _tape.first;
    while (_tape.length <= r) {
      _tape.add(_rand());
    }
    return _tape[r];
  }

  void startSpin() {
    if (_spinning) return;
    _spinning = true;
    _stopping = false;
    _blur = 2.5;
    _last = Duration.zero;
    _ticker.start();
  }

  /// Lands the reel on [col] = [top, payline, bottom]. Completes when it settles.
  Future<void> stopTo(List<SlotSymbol> col, {bool fast = false}) {
    if (!_spinning) {
      setState(() => _tape = List.of(col));
      _pos = 0;
      return Future.value();
    }
    final target = _pos.ceil() + (fast ? 3 : 6);
    while (_tape.length < target + 6) {
      _tape.add(_rand());
    }
    for (var i = 0; i < 3; i++) {
      _tape[target + i] = col[i];
    }
    _from = _pos;
    _to = target.toDouble();
    _dur = Duration(milliseconds: fast ? 260 : 520);
    _t0 = _last;
    _stopping = true;
    _done = Completer<void>();
    return _done!.future;
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_stopping) {
      final u = ((elapsed - _t0).inMicroseconds / _dur.inMicroseconds).clamp(0.0, 1.0);
      _pos = _from + (_to - _from) * _curve.transform(u);
      _blur = 2.5 * (1 - u);
      if (u >= 1) {
        final finalCol = [_at(_to.round()), _at(_to.round() + 1), _at(_to.round() + 2)];
        _tape = finalCol;
        _pos = 0;
        _spinning = false;
        _stopping = false;
        _blur = 0;
        _ticker.stop();
        _done?.complete();
        _done = null;
      }
    } else if (_spinning) {
      _pos += dt * 15; // rows per second
      if (_pos > 40) {
        final n = _pos.floor() - 2;
        _tape.removeRange(0, math.min(n, _tape.length));
        _pos -= n;
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final moving = _spinning || _stopping;
    final base = _pos.floor() - 1;
    final cells = <Widget>[];
    for (var r = base; r <= base + 4; r++) {
      final y = _cellTop + (r - _pos) * _pitch;
      final o = moving ? 1.0 : 1.0 - 0.45 * math.min(1.0, (y - 31).abs() / _pitch);
      cells.add(Positioned(
        left: 7,
        top: y,
        child: Opacity(opacity: o, child: SymbolView(_at(r))),
      ));
    }

    Widget strip = SizedBox(width: 78, height: 126, child: Stack(children: cells));
    if (_blur > 0.05) {
      strip = ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 0.4, sigmaY: _blur), child: strip);
    }

    return Container(
      width: 78,
      height: 126,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFCFCDC6), Color(0xFFF4F3EE), Color(0xFFF7F6F2), Color(0xFFF4F3EE), Color(0xFFCFCDC6)],
          stops: [0, 0.24, 0.5, 0.76, 1],
        ),
        boxShadow: widget.highlight
            ? const [
                BoxShadow(color: kGold, spreadRadius: 2),
                BoxShadow(color: Color(0xBFFFC83D), blurRadius: 18, spreadRadius: 2),
              ]
            : null,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x59000000)),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x6B000000), Color(0x00000000), Color(0x00000000), Color(0x6B000000)],
          stops: [0, 0.3, 0.7, 1],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: strip,
    );
  }
}
