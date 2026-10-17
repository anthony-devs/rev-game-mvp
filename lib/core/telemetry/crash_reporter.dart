import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';

/// Sends app crashes to our own server (shown on the founder's Insights page and the developer
/// console), grouped by bug. No extra package and nothing leaves the app until a crash happens.
///
/// - Reports only when the player is signed in (the server needs to know the request is real).
/// - The same crash is sent once per app run, at most [_maxPerRun] different ones per run.
/// - Reporting can never throw or crash the app.
///
/// Set the version with `--dart-define=APP_VERSION=1.2.3`.
class CrashReporter {
  CrashReporter._();

  static const String appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');
  static const int _maxPerRun = 15;

  static ApiClient? _api;
  static final Set<String> _sent = <String>{};

  /// Call once in `main()`, after the [ApiClient] exists.
  static void install(ApiClient api) {
    _api = api;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details); // keep Flutter's normal console output
      report(details.exception, details.stack, library: details.library);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack);
      return true; // handled: don't kill the app
    };
  }

  /// Report something you caught yourself and want to know about.
  static void report(Object error, StackTrace? stack, {String? library}) {
    final api = _api;
    if (api == null || kDebugMode) return; // debug builds already show the error on screen
    try {
      final kind = error.runtimeType.toString();
      final stackText = (stack ?? StackTrace.current).toString();
      final firstLines = stackText.split('\n').take(6).join('|');
      final key = '$kind|${firstLines.replaceAll(RegExp(r'\d+'), '#')}';
      if (_sent.length >= _maxPerRun || !_sent.add(key)) return;
      api
          .post('/v1/telemetry/crash', {
            'kind': kind,
            'message': _cut(error.toString(), 300),
            'stack': _cut(stackText, 2500),
            'platform': Platform.operatingSystem,
            'appVersion': appVersion,
            if (library != null) 'library': library,
          })
          .catchError((_) => <String, dynamic>{});
    } catch (_) {
      // never let reporting cause a problem of its own
    }
  }

  static String _cut(String s, int n) => s.length <= n ? s : s.substring(0, n);
}
