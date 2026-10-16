import 'dart:async';
import 'dart:math';

import '../core/api/api_client.dart';
import '../model/model_json.dart';
import 'crash_server.dart';

/// Dash Crash backed by the real game server.
///
/// The server decides the crash point and never sends it early. This class
/// draws the same curve locally from the server's growth rate so the animation
/// is smooth, then obeys the server's `crashed` and `cashedOut` events.
class ApiCrashServer implements CrashServer {
  ApiCrashServer(this._api, {required this.balance});

  final ApiClient _api;

  @override
  double balance;

  StreamController<RoundEvent>? _ctrl;
  StreamSubscription<SseEvent>? _events;
  Timer? _timer;
  String? _roundId;

  @override
  String? get roundId => _roundId;
  bool _settled = false; // cashed out
  double _growth = 0.12;
  final Stopwatch _clock = Stopwatch();
  Duration _offset = Duration.zero;

  @override
  Stream<RoundEvent> startRound({required double bet, double? autoCashout}) {
    _reset();
    final before = balance;
    balance -= bet; // show the bet leaving at once; the server confirms below
    final ctrl = StreamController<RoundEvent>();
    _ctrl = ctrl;
    unawaited(_run(ctrl, bet, autoCashout, before));
    return ctrl.stream;
  }

  Future<void> _run(StreamController<RoundEvent> ctrl, double bet, double? auto, double before) async {
    final sent = Stopwatch()..start();
    try {
      final res = await _api.post('/v1/crash/rounds', {'bet': bet, if (auto != null) 'autoCashout': auto});
      if (ctrl.isClosed) return;
      _roundId = parseString(res['roundId']);
      balance = parseDouble(res['balance'], balance);
      _growth = parseDouble(res['growthRate'], 0.12);

      // The round started on the server about half a round trip ago.
      _offset = sent.elapsed ~/ 2;
      _clock
        ..reset()
        ..start();
      _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());

      _events = _api.events('/v1/crash/rounds/$_roundId/events').listen(
            _onServerEvent,
            onError: (Object e) {
              // Lost the stream. The server still settles the round, and the
              // wallet in Firestore shows the result.
              if (!ctrl.isClosed) ctrl.addError(e);
              _finish();
            },
          );
    } catch (e) {
      balance = before; // the bet was never taken
      if (!ctrl.isClosed) {
        ctrl.addError(e);
        await ctrl.close();
      }
    }
  }

  void _tick() {
    final ctrl = _ctrl;
    if (ctrl == null || ctrl.isClosed) return;
    final seconds = (_clock.elapsed + _offset).inMicroseconds / 1e6;
    ctrl.add(RoundEvent.tick(exp(_growth * seconds), balance));
  }

  void _onServerEvent(SseEvent e) {
    final ctrl = _ctrl;
    if (ctrl == null || ctrl.isClosed) return;
    switch (e.name) {
      case 'cashedOut':
        _applyCashout(e.data);
        break;
      case 'crashed':
        balance = parseDouble(e.data['balance'], balance);
        ctrl.add(RoundEvent.crashed(parseDouble(e.data['crashPoint'], 1), balance));
        _finish();
        break;
    }
  }

  void _applyCashout(Json d) {
    if (_settled) return;
    _settled = true;
    balance = parseDouble(d['balance'], balance);
    _ctrl?.add(RoundEvent.cashedOut(parseDouble(d['multiplier']), parseDouble(d['payout']), balance));
  }

  @override
  void cashOut() {
    final id = _roundId;
    if (id == null || _settled || _ctrl == null) return;
    _api.post('/v1/crash/rounds/$id/cashout').then(_applyCashout).catchError((Object _) {
      // too_late: the crashed event is on its way. Network error: nothing paid.
    });
  }

  void _finish() {
    _timer?.cancel();
    _events?.cancel();
    final ctrl = _ctrl;
    _ctrl = null;
    ctrl?.close();
  }

  void _reset() {
    _timer?.cancel();
    _events?.cancel();
    _ctrl?.close();
    _ctrl = null;
    _settled = false;
  }

  @override
  void dispose() => _reset();
}
