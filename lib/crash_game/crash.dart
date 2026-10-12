// ignore_for_file: constant_identifier_names

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The three character states. The enum names match the folder names under
/// assets/Crash_assets/character/ exactly (Idle, Run, Dead).
enum CrashState { Idle, Run, Dead }

/// Number of frames per state. Set each one to the number of PNGs in that folder.
/// Idle__000.png ... Idle__009.png means 10.
const Map<CrashState, int> _frameCounts = {
  CrashState.Idle: 10,
  CrashState.Run: 8,
  CrashState.Dead: 10,
};

/// Builds the frame list for one animation, e.g.
/// assets/Crash_assets/character/Idle/Idle__000.png
List<ImageProvider> seq(String name, int count) => List.generate(
      count,
      (i) => AssetImage(
        'assets/Crash_assets/character/$name/${name}__${i.toString().padLeft(3, '0')}.png',
      ),
    );

// Top-level finals are created once, so the lists stay stable across rebuilds.
final Map<CrashState, List<ImageProvider>> _frames = {
  for (final s in CrashState.values) s: seq(s.name, _frameCounts[s]!),
};

/// Optional: decode every frame of every state up front, e.g. from a page's
/// didChangeDependencies, so the first state change never stutters.
Future<void> precacheCrashFrames(BuildContext context) => Future.wait(
      _frames.values.expand((l) => l).map((f) => precacheImage(f, context)),
    );

/// Shows the right animation for the current game state.
class CrashCharacter extends StatelessWidget {
  const CrashCharacter({
    super.key,
    required this.state,
    this.height = 280,
  });

  final CrashState state;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FrameAnimation(
      frames: _frames[state]!,
      fps: state == CrashState.Run ? 18 : 10,
      loop: state != CrashState.Dead, // the crash plays once and holds the last frame
      height: height,
    );
  }
}

/// Plays a list of images frame by frame.
class FrameAnimation extends StatefulWidget {
  const FrameAnimation({
    super.key,
    required this.frames,
    this.fps = 9,
    this.loop = true,
    this.height,
  });

  final List<ImageProvider> frames;
  final double fps;
  final bool loop;
  final double? height;

  @override
  State<FrameAnimation> createState() => _FrameAnimationState();
}

class _FrameAnimationState extends State<FrameAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  bool _started = false;
  bool _ready = false;
  int _token = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // precacheImage needs a context with MediaQuery, so it can't run in
    // initState. The guard stops later dependency changes from restarting it.
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void didUpdateWidget(FrameAnimation old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.frames, widget.frames) ||
        old.fps != widget.fps ||
        old.loop != widget.loop) {
      _load();
    }
  }

  Future<void> _load() async {
    final token = ++_token;
    _c.stop();
    final frames = widget.frames;

    // Decode every frame up front so playback never flickers. After the first
    // load, gaplessPlayback keeps the previous image on screen while the next
    // state's frames load, so switching states never flashes blank.
    await Future.wait(frames.map((f) => precacheImage(f, context)));
    if (!mounted || token != _token) return;

    _c
      ..duration = Duration(
        milliseconds: (frames.length / widget.fps * 1000).round(),
      )
      ..value = 0;
    widget.loop ? _c.repeat() : _c.forward();
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return SizedBox(height: widget.height);
    final n = widget.frames.length;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final i = (_c.value * n).floor().clamp(0, n - 1);
        return Image(
          image: widget.frames[i],
          height: widget.height,
          gaplessPlayback: true,
        );
      },
    );
  }
}

/// Quick test screen: tap a state and watch the animation change.
class CrashCharacterDemo extends StatefulWidget {
  const CrashCharacterDemo({super.key});

  @override
  State<CrashCharacterDemo> createState() => _CrashCharacterDemoState();
}

class _CrashCharacterDemoState extends State<CrashCharacterDemo> {
  CrashState _state = CrashState.Idle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Center(child: CrashCharacter(state: _state)),
            const SizedBox(height: 32),
            SegmentedButton<CrashState>(
              segments: const [
                ButtonSegment(value: CrashState.Idle, label: Text('Idle')),
                ButtonSegment(value: CrashState.Run, label: Text('Run')),
                ButtonSegment(value: CrashState.Dead, label: Text('Dead')),
              ],
              selected: {_state},
              onSelectionChanged: (s) => setState(() => _state = s.first),
            ),
          ],
        ),
      ),
    );
  }
}