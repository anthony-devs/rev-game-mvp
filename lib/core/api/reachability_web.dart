// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Browsers report this themselves.
Future<bool> deviceHasInternet() async => html.window.navigator.onLine ?? true;
