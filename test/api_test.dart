import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rev_game_mvp/core/api/api_client.dart';
import 'package:rev_game_mvp/slots_game/api_slots_server.dart';
import 'package:rev_game_mvp/slots_game/slots_models.dart';

ApiClient clientFor(MockClient mock) =>
    ApiClient(tokenProvider: () async => 'token', client: mock, baseUrl: 'http://test');

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  test('sends the Firebase token', () async {
    String? seen;
    final api = clientFor(MockClient((req) async {
      seen = req.headers['Authorization'];
      return json({'ok': true});
    }));
    await api.get('/v1/wallet');
    expect(seen, 'Bearer token');
  });

  test('server errors become ApiException', () async {
    final api = clientFor(MockClient((req) async => json({'error': 'insufficient_credits', 'message': 'Not enough credits.'}, 402)));
    expect(
      api.post('/v1/slots/spin', {'bet': 100}),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'insufficient_credits').having((e) => e.status, 'status', 402)),
    );
  });

  test('no token means unauthenticated, before any request', () async {
    final api = ApiClient(tokenProvider: () async => null, client: MockClient((req) async => json({})), baseUrl: 'http://test');
    expect(api.get('/v1/wallet'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
  });

  test('spin result is parsed', () async {
    final api = clientFor(MockClient((req) async => json({
          'columns': [
            ['bar', 'seven', 'cherry'],
            ['bell', 'seven', 'bar'],
            ['cherry', 'seven', 'diamond'],
          ],
          'multiplier': 100,
          'payout': 10000,
          'balanceAfterBet': 9900,
          'balance': 19900,
          'label': '3x Seven - pays x100',
        })));
    final r = await ApiSlotsServer(api).spin(100);
    expect(r.columns[1][1], SlotSymbol.seven);
    expect(r.isWin, isTrue);
    expect(r.balanceAfter, 19900);
  });

  test('server-sent events are parsed and pings ignored', () async {
    const body = ': ping\n\nevent: cashedOut\ndata: {"multiplier": 2.0, "payout": 200, "balance": 10100}\n\nevent: crashed\ndata: {"crashPoint": 9.7, "balance": 10100}\n\n';
    final mock = MockClient.streaming((req, _) async {
      return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
    });
    final events = await clientFor(mock).events('/v1/crash/rounds/x/events').toList();
    expect(events.map((e) => e.name), ['cashedOut', 'crashed']);
    expect(events.first.data['payout'], 200);
  });
}
