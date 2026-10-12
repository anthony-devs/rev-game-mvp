import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
  bool _ready = false;
  int _token = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
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
    _ready = false; // a build always follows this call
    _c.stop();
    final frames = widget.frames;
    // Decode every frame up front so playback never flickers.
    await Future.wait(frames.map((f) => precacheImage(f, context)));
    if (!mounted || token != _token) return;
    _c
      ..duration = Duration(milliseconds: (frames.length / widget.fps * 1000).round())
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