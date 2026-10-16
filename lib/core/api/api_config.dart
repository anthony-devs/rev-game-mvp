import 'package:flutter/foundation.dart';

/// Where the game server lives. Set it when you run or build the app:
///
/// ```
/// flutter run --dart-define=API_URL=https://rev-game-server-xxxx.a.run.app
/// ```
class ApiConfig {
  ApiConfig._();

  static const String _override = String.fromEnvironment('API_URL');

  static String get baseUrl {
    if (_override.isNotEmpty) return _override.endsWith('/') ? _override.substring(0, _override.length - 1) : _override;
    // Local server: the Android emulator reaches your computer at 10.0.2.2.
    return defaultTargetPlatform == TargetPlatform.android ? 'http://10.0.2.2:8080' : 'http://localhost:8080';
  }
}
