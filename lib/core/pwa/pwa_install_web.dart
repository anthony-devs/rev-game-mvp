// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js_util' as js;

/// Install support for the web build. index.html catches the browser's install event early and keeps
/// it on `window.__revInstall`, so it is never missed while the app is still loading.
class PwaInstall {
  PwaInstall._();

  static bool get _standalone {
    final byQuery = html.window.matchMedia('(display-mode: standalone)').matches;
    final byIos = js.getProperty<Object?>(html.window.navigator, 'standalone') == true;
    return byQuery || byIos;
  }

  static bool get isIos {
    final ua = html.window.navigator.userAgent.toLowerCase();
    final touchMac = ua.contains('macintosh') && (html.window.navigator.maxTouchPoints ?? 0) > 1;
    return ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod') || touchMac;
  }

  static bool get canPrompt => js.getProperty<Object?>(html.window, '__revInstall') != null;

  static bool get canOffer => !_standalone;

  static Future<bool> prompt() async {
    final event = js.getProperty<Object?>(html.window, '__revInstall');
    if (event == null) return false;
    try {
      js.callMethod<Object?>(event, 'prompt', const []);
      final choice = await js.promiseToFuture<Object?>(js.getProperty<Object>(event, 'userChoice'));
      js.setProperty(html.window, '__revInstall', null);
      return js.getProperty<Object?>(choice!, 'outcome') == 'accepted';
    } catch (_) {
      return false;
    }
  }
}
