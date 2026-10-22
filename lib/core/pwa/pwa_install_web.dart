import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Install support for the web build. index.html catches the browser's install event early and keeps
/// it on `window.__revInstall`, so it is never missed while the app is still loading.
class PwaInstall {
  PwaInstall._();

  static bool get _standalone {
    final byQuery = web.window.matchMedia('(display-mode: standalone)').matches;
    final byIos = web.window.navigator['standalone'].dartify() == true;
    return byQuery || byIos;
  }

  static bool get isIos {
    final ua = web.window.navigator.userAgent.toLowerCase();
    final touchMac = ua.contains('macintosh') && web.window.navigator.maxTouchPoints > 1;
    return ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod') || touchMac;
  }

  static JSAny? get _event => web.window.getProperty<JSAny?>('__revInstall'.toJS);

  static bool get canPrompt => _event != null;

  static bool get canOffer => !_standalone;

  static Future<bool> prompt() async {
    final event = _event;
    if (event == null) return false;
    try {
      final e = event as JSObject;
      e.callMethod<JSAny?>('prompt'.toJS);
      final choice = await (e['userChoice'] as JSPromise<JSAny?>).toDart;
      web.window.setProperty('__revInstall'.toJS, null);
      return (choice as JSObject)['outcome'].dartify() == 'accepted';
    } catch (_) {
      return false;
    }
  }
}
