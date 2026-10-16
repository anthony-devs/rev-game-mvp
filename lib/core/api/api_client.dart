import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../model/model_json.dart';
import 'api_config.dart';

/// An error from the game server (or from reaching it).
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message, [this.data = const {}]);

  /// 0 means the request never reached the server.
  final int status;
  final String code;
  final String message;
  final Json data;

  bool get isNetwork => status == 0;

  @override
  String toString() => 'ApiException($status, $code, $message)';
}

class SseEvent {
  const SseEvent(this.name, this.data);
  final String name;
  final Json data;
}

/// Small JSON client for the game server. Adds the Firebase ID token to every
/// request and turns failures into [ApiException].
class ApiClient {
  ApiClient({required Future<String?> Function() tokenProvider, http.Client? client, String? baseUrl})
      : _token = tokenProvider,
        _http = client ?? http.Client(),
        _base = baseUrl ?? ApiConfig.baseUrl;

  final Future<String?> Function() _token;
  final http.Client _http;
  final String _base;

  static const Duration _timeout = Duration(seconds: 15);

  Future<Json> get(String path) => _call(() async => _http.get(await _uri(path), headers: await _headers()));

  Future<Json> post(String path, [Json? body]) {
    return _call(() async => _http.post(await _uri(path), headers: await _headers(json: true), body: jsonEncode(body ?? {})));
  }

  Future<Json> delete(String path) =>
      _call(() async => _http.delete(await _uri(path), headers: await _headers()));

  /// Server-sent events. Cancel the subscription to close the connection.
  Stream<SseEvent> events(String path) async* {
    final request = http.Request('GET', await _uri(path))..headers.addAll(await _headers(sse: true));
    final http.StreamedResponse response;
    try {
      response = await _http.send(request).timeout(_timeout);
    } on SocketException {
      throw _offline();
    } on TimeoutException {
      throw _offline();
    } on http.ClientException {
      throw _offline();
    }
    if (response.statusCode != 200) {
      throw _fromResponse(response.statusCode, await response.stream.bytesToString());
    }

    String? name;
    final data = StringBuffer();
    try {
      await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.isEmpty) {
          if (name != null) yield SseEvent(name, _decode(data.toString()));
          name = null;
          data.clear();
        } else if (line.startsWith('event:')) {
          name = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          data.write(line.substring(5).trim());
        } // lines starting with ":" are keep-alive pings
      }
    } on SocketException {
      throw _offline();
    } on http.ClientException {
      throw _offline();
    }
  }

  // ---- internals -----------------------------------------------------------

  Future<Uri> _uri(String path) async => Uri.parse('$_base$path');

  Future<Map<String, String>> _headers({bool json = false, bool sse = false}) async {
    final token = await _token();
    if (token == null) throw const ApiException(401, 'unauthenticated', 'Sign in to continue.');
    return {
      'Authorization': 'Bearer $token',
      if (json) 'Content-Type': 'application/json',
      if (sse) 'Accept': 'text/event-stream',
    };
  }

  Future<Json> _call(Future<http.Response> Function() send) async {
    try {
      final res = await send().timeout(_timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) return _decode(res.body);
      throw _fromResponse(res.statusCode, res.body);
    } on SocketException {
      throw _offline();
    } on TimeoutException {
      throw _offline();
    } on http.ClientException {
      throw _offline();
    }
  }

  ApiException _offline() =>
      const ApiException(0, 'network', 'Cannot reach the game server. Check your connection and try again.');

  ApiException _fromResponse(int status, String body) {
    final json = _decode(body);
    return ApiException(
      status,
      parseString(json['error']) ?? 'server_error',
      parseString(json['message']) ?? 'Something went wrong. Please try again.',
      json,
    );
  }

  Json _decode(String body) {
    try {
      return parseMap(jsonDecode(body));
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  void close() => _http.close();
}
