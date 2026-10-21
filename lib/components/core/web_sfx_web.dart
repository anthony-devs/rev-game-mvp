import 'dart:async';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:web_audio';

/// Sound effects for the browser, through the Web Audio API. Every file is decoded once into memory,
/// so a sound starts the moment it is asked for. (An HTML audio element reloads and starts late.)
class WebSfx {
  WebSfx._();

  static AudioContext? _ctx;
  static final Map<String, AudioBuffer> _buffers = {};
  static Future<void>? _loading;

  static AudioContext get _c => _ctx ??= AudioContext();

  static bool _unlockHooked = false;

  /// Phones keep the sound system locked until the first touch. Open it on the very first touch or click
  /// (and play a silent blip), so the first real sound is not lost or late.
  static void _hookUnlock() {
    if (_unlockHooked) return;
    _unlockHooked = true;
    void unlock(html.Event _) {
      try {
        final c = _c;
        unawaited(c.resume());
        final src = c.createBufferSource()..buffer = c.createBuffer(1, 1, 22050);
        src.connectNode(c.destination!);
        src.start(0);
      } catch (_) {}
    }

    for (final type in const ['touchstart', 'touchend', 'pointerdown', 'mousedown', 'click', 'keydown']) {
      html.document.addEventListener(type, unlock, true);
    }
  }

  static Future<void> preload(List<String> files) => _loading ??= () async {
        _hookUnlock();
        final c = _c;
        await Future.wait(files.map((f) async {
          try {
            final req = await html.HttpRequest.request('assets/assets/sounds/$f.wav', responseType: 'arraybuffer');
            _buffers[f] = await c.decodeAudioData(req.response as ByteBuffer);
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
        gain.gain?.value = volume;
        src.connectNode(gain);
        gain.connectNode(c.destination!);
        src.start(0);
      }

      if (c.state == 'running') {
        go();
      } else {
        // Still locked (first sound): start as soon as the browser lets it.
        c.resume().then((_) => go()).catchError((_) {});
      }
    } catch (_) {}
  }
}
