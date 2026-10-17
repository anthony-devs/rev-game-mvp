import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../components/core/play_mode.dart';
import '../../model/model_json.dart';
import 'api_config.dart';
import 'rounds_hub.dart';
import 'reachability.dart';

/// An error from the game server (or from reaching it).
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message, [this.data = const {}]);

  /// 0 means the request never reached the server.
  final int status;
  final String code;
  final String message;
  final Json data;

  /// The request never got an answer (either [isOffline] or [isServerDown]).
  bool get isNetwork => status == 0;

  /// The phone has no internet connection.
  bool get isOffline => code == 'network';

  /// The phone is online but our service did not answer, or answered that it is down.
  bool get isServerDown => code == 'unreachable' || code == 'service_unavailable' || code == 'database_busy' || status == 502 || status == 503 || status == 504;

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
  ApiClient({
    required Future<String?> Function() tokenProvider,
    Future<String?> Function()? tokenRefresher,
    http.Client? client,
    String? baseUrl,
  })  : _token = tokenProvider,
        _refresh = tokenRefresher,
        _http = client ?? http.Client(),
        _base = baseUrl ?? ApiConfig.baseUrl;

  final Future<String?> Function() _token;

  /// Gets a brand new ID token. Used once when the server says the token was refused.
  final Future<String?> Function()? _refresh;
  final http.Client _http;
  final String _base;

  static const Duration _timeout = Duration(seconds: 15);

  Future<Json> get(String path, {Duration? timeout}) =>
      _call((fresh) async => _http.get(await _uri(path), headers: await _headers(fresh: fresh)), timeout: timeout);

  Future<Json> post(String path, [Json? body]) {
    return _call((fresh) async => _http.post(await _uri(path), headers: await _headers(json: true, fresh: fresh), body: jsonEncode(body ?? {})));
  }

  Future<Json> delete(String path) =>
      _call((fresh) async => _http.delete(await _uri(path), headers: await _headers(fresh: fresh)));

  /// Sends one file as multipart form data (field name `file`).
  Future<Json> upload(String path, String filePath, {required String filename}) async {
    try {
      final request = http.MultipartRequest('POST', await _uri(path))
        ..headers.addAll(await _headers())
        ..files.add(await http.MultipartFile.fromPath('file', filePath, filename: filename));
      final streamed = await _http.send(request).timeout(const Duration(seconds: 120));
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode >= 200 && res.statusCode < 300) return _decode(res.body);
      throw _fromResponse(res.statusCode, res.body);
    } on SocketException {
      throw await _unreachable();
    } on TimeoutException {
      throw await _unreachable();
    } on http.ClientException {
      throw await _unreachable();
    }
  }

  /// Downloads a file (an attachment) as bytes.
  Future<Uint8List> getBytes(String path) async {
    try {
      final res = await _http.get(await _uri(path), headers: await _headers()).timeout(const Duration(seconds: 60));
      if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
      throw _fromResponse(res.statusCode, res.body);
    } on SocketException {
      throw await _unreachable();
    } on TimeoutException {
      throw await _unreachable();
    } on http.ClientException {
      throw await _unreachable();
    }
  }

  /// Server-sent events. Cancel the subscription to close the connection.
  Stream<SseEvent> events(String path) async* {
    final request = http.Request('GET', await _uri(path))..headers.addAll(await _headers(sse: true));
    final http.StreamedResponse response;
    try {
      response = await _http.send(request).timeout(_timeout);
    } on SocketException {
      throw await _unreachable();
    } on TimeoutException {
      throw await _unreachable();
    } on http.ClientException {
      throw await _unreachable();
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
      throw await _unreachable();
    } on http.ClientException {
      throw await _unreachable();
    }
  }

  // ---- internals -----------------------------------------------------------

  Future<Uri> _uri(String path) async => Uri.parse('$_base$path');

  Future<Map<String, String>> _headers({bool json = false, bool sse = false, bool fresh = false}) async {
    final token = await ((fresh ? _refresh : null) ?? _token)();
    if (token == null) throw const ApiException(401, 'unauthenticated', 'Sign in to continue.');
    return {
      'Authorization': 'Bearer $token',
      if (json) 'Content-Type': 'application/json',
      if (sse) 'Accept': 'text/event-stream',
      // Live mode plays on the real-money wallet. The server only looks at this on game requests.
      if (PlayMode.isLive) 'X-Play-Mode': 'live',
    };
  }

  Future<Json> _call(Future<http.Response> Function(bool fresh) send, {Duration? timeout}) async {
    try {
      var res = await send(false).timeout(timeout ?? _timeout);
      // The server refused the token (expired, or the phone clock is off): get a new one and try once more.
      if (res.statusCode == 401 && _refresh != null) {
        res = await send(true).timeout(timeout ?? _timeout);
      }
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final json = _decode(res.body);
        RoundsHub.apply(json); // every round answer says how many rounds are left
        return json;
      }
      throw _fromResponse(res.statusCode, res.body);
    } on SocketException {
      throw await _unreachable();
    } on TimeoutException {
      throw await _unreachable();
    } on http.ClientException {
      throw await _unreachable();
    }
  }

  /// Nothing came back. Works out why: no internet on the phone, or our service is down.
  Future<ApiException> _unreachable() async {
    if (!await deviceHasInternet()) {
      return const ApiException(0, 'network', "You're offline. Check your internet connection and try again.");
    }
    return const ApiException(0, 'unreachable', "We're experiencing downtime. Please try again in a few minutes. Your balance is safe.");
  }

  ApiException _fromResponse(int status, String body) {
    final json = _decode(body);
    final code = parseString(json['error']) ?? 'server_error';
    if (code == 'no_rounds') RoundsHub.applyRefusal(json);
    return ApiException(status, code, _friendly(status, code, parseString(json['message'])), json);
  }

  /// Players never see technical words (database, quota, server error). Rule messages from the
  /// server ("Bet is too low", "Insufficient balance") pass through; anything that is our problem
  /// becomes a calm sentence.
  static String _friendly(int status, String code, String? message) {
    switch (code) {
      case 'maintenance':
        return message ?? "We're making things better. Back shortly.";
      case 'service_unavailable':
        return "We're experiencing downtime. Please try again in a few minutes. Your balance is safe.";
      case 'database_busy':
        return "We're very busy right now. Please try again in a few minutes.";
      case 'not_initialized':
        return "We're getting things ready. Please try again in a few minutes.";
      case 'unauthenticated':
        return 'Please sign in again to continue.';
    }
    if (status == 429) return 'Too many tries. Please wait a moment and try again.';
    if (status == 502 || status == 503 || status == 504) return "We're experiencing downtime. Please try again in a few minutes. Your balance is safe.";
    if (status >= 500) return 'Something went wrong on our side. Please try again in a moment.';
    return message ?? 'Something went wrong. Please try again.';
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
