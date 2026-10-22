import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Sound effects for the browser, through the Web Audio API. Every file is decoded once into memory,
/// so a sound starts the moment it is asked for. (An HTML audio element reloads and starts late.)
class WebSfx {
  WebSfx._();

  static web.AudioContext? _ctx;
  static final Map<String, web.AudioBuffer> _buffers = {};
  static Future<void>? _loading;

  static web.AudioContext get _c => _ctx ??= web.AudioContext();

  static bool _unlockHooked = false;

  /// Phones keep the sound system locked until the first touch. Open it on the very first touch or click
  /// (and play a silent blip), so the first real sound is not lost or late.
  static void _hookUnlock() {
    if (_unlockHooked) return;
    _unlockHooked = true;
    void unlock(web.Event _) {
      try {
        final c = _c;
        unawaited(c.resume().toDart);
        final src = c.createBufferSource()..buffer = c.createBuffer(1, 1, 22050);
        src.connect(c.destination);
        src.start(0);
      } catch (_) {}
    }

    final fn = unlock.toJS;
    for (final type in const ['touchstart', 'touchend', 'pointerdown', 'mousedown', 'click', 'keydown']) {
      web.document.addEventListener(type, fn, true.toJS);
    }
  }

  static Future<void> preload(List<String> files) => _loading ??= () async {
        _hookUnlock();
        final c = _c;
        await Future.wait(files.map((f) async {
          try {
            final res = await web.window.fetch('assets/assets/sounds/$f.wav'.toJS).toDart;
            if (!res.ok) return;
            final bytes = await res.arrayBuffer().toDart;
            _buffers[f] = await c.decodeAudioData(bytes).toDart;
          } catch (_) {}
        }));
      }();

  /// Call it straight from the tap, so the browser lets the sound start.
  static void play(String file, double volume) {
    try {
      final c = _c;
      final buffer = _buffers[file];
      if (buffer == null) return;
      void go() {
        final src = c.createBufferSource()..buffer = buffer;
        final gain = c.createGain();
        gain.gain.value = volume;
        src.connect(gain);
        gain.connect(c.destination);
        src.start(0);
      }

      if (c.state == 'running') {
        go();
      } else {
        // Still locked (first sound): start as soon as the browser lets it.
        c.resume().toDart.then((_) => go(), onError: (_) {});
      }
    } catch (_) {}
  }
}
