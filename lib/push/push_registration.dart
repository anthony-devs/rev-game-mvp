import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../core/app_version.dart';

/// Registers this phone for push notifications so the team can send announcements from the admin
/// dashboard. Asks permission once the player is signed in; never blocks the app if anything fails.
class PushRegistration {
  PushRegistration._();

  static ApiClient? _api;
  static String? _token;
  static StreamSubscription<String>? _refresh;

  static Future<void> start(ApiClient api) async {
    _api = api;
    if (kIsWeb || AppVersion.platform.isEmpty) return;
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;
      await messaging.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
      _refresh ??= messaging.onTokenRefresh.listen(_send, onError: (_) {});
      // On iPhone the push address arrives a moment after permission is granted.
      if (AppVersion.platform == 'ios') {
        for (var i = 0; i < 8 && await messaging.getAPNSToken() == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
      final token = await messaging.getToken();
      if (token != null) await _send(token);
    } catch (e) {
      debugPrint('Push setup skipped: $e');
    }
  }

  static Future<void> _send(String token) async {
    _token = token;
    try {
      await _api?.post('/v1/push/token', {'token': token, 'platform': AppVersion.platform});
    } catch (_) {
      // Not signed in yet, or offline. It registers again next time the app starts.
    }
  }

  /// Called just before sign-out so this phone stops getting the previous player's messages.
  static Future<void> stop() async {
    final token = _token;
    if (token == null) return;
    try {
      await _api?.post('/v1/push/unregister', {'token': token});
    } catch (_) {}
  }
}
