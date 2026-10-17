import 'dart:async';
import 'dart:io';

DateTime _at = DateTime.fromMillisecondsSinceEpoch(0);
bool _last = true;
Future<bool>? _running;

/// True when the phone can reach the internet (not our server, any public host).
/// Opens a quick connection to two well known public addresses; one success is enough.
/// The answer is reused for 3 seconds so a burst of failed calls probes once.
Future<bool> deviceHasInternet() {
  if (DateTime.now().difference(_at) < const Duration(seconds: 3)) return Future.value(_last);
  return _running ??= _probe().whenComplete(() => _running = null);
}

Future<bool> _probe() async {
  final done = Completer<bool>();
  var pending = 3;
  void finish(bool ok) {
    if (done.isCompleted) return;
    if (ok) {
      done.complete(true);
    } else if (--pending == 0) {
      done.complete(false);
    }
  }

  Future<void> tryHost(String host, int port) async {
    try {
      final s = await Socket.connect(host, port, timeout: const Duration(seconds: 3));
      s.destroy();
      finish(true);
    } catch (_) {
      finish(false);
    }
  }

  unawaited(tryHost('1.1.1.1', 443));
  unawaited(tryHost('8.8.8.8', 443));
  unawaited(() async {
    try {
      final r = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 3));
      finish(r.isNotEmpty);
    } catch (_) {
      finish(false);
    }
  }());
  final ok = await done.future;
  _last = ok;
  _at = DateTime.now();
  return ok;
}
