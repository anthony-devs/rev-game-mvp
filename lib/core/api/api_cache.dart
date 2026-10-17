import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the last answer of a few reads so a screen can show something the moment it opens and
/// refresh behind it. It never stores money-changing actions, only things that are safe to show a
/// little late (the legal pages, rounds left, payment methods). Everything is best effort: if storage
/// is unavailable the screen simply loads as before.
class ApiCache {
  ApiCache._();

  static const _prefix = 'cache.';

  static Future<Map<String, dynamic>?> read(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('$_prefix$key');
      if (raw == null) return null;
      final v = jsonDecode(raw);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, Map<String, dynamic> value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('$_prefix$key', jsonEncode(value));
    } catch (_) {}
  }

  static Future<void> remove(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove('$_prefix$key');
    } catch (_) {}
  }

  /// Forget everything (sign out, so the next player never sees someone else's last state).
  static Future<void> clear() async {
    try {
      final p = await SharedPreferences.getInstance();
      for (final k in p.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
        await p.remove(k);
      }
    } catch (_) {}
  }
}
