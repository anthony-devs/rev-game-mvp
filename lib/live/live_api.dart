import '../core/api/api_client.dart';
import '../model/model_json.dart';
import 'live_models.dart';

/// Real-money endpoints. The server decides everything; the app only asks.
///
/// Every deposit and payout carries an idempotency [key]: sending the same key twice
/// (a double tap, a retry after a slow connection) returns the same payment, never a second one.
class LiveApi {
  LiveApi(this._api);
  final ApiClient _api;

  Future<LiveStatus> status() async => LiveStatus.fromJson(await _api.get('/v1/live/status'));

  Future<List<LivePayment>> payments() async {
    final j = await _api.get('/v1/live/payments');
    return [for (final p in (j['payments'] as List? ?? const [])) LivePayment.fromJson(parseMap(p))];
  }

  Future<LivePayment> deposit({required String provider, required double amount, required String key}) async =>
      LivePayment.fromJson(await _api.post('/v1/live/deposits', {'provider': provider, 'amount': amount, 'key': key}));

  /// Asks the server to check with the payment provider. The server coins the wallet, never the app.
  Future<LivePayment> verify(String id) async => LivePayment.fromJson(await _api.post('/v1/live/deposits/$id/verify'));

  /// Mock gateways only: what the customer does on the provider's own page.
  Future<void> mockPay(String id, {required bool success}) async {
    await _api.post('/v1/live/mock/pay', {'paymentId': id, 'outcome': success ? 'success' : 'fail'});
  }

  /// [destination] depends on the method: bank (`bankName`, `accountName`, `accountNumber`),
  /// crypto (`address`) or PayPal (`email`).
  Future<LivePayment> payout({
    required String provider,
    required double amount,
    required Map<String, String> destination,
    required String key,
  }) async =>
      LivePayment.fromJson(await _api.post('/v1/live/payouts', {'provider': provider, 'amount': amount, 'key': key, 'destination': destination}));

  Future<LiveAgreement> agreement() async => LiveAgreement.fromJson(await _api.get('/v1/live/agreement'));

  Future<void> acceptAgreement(String version, List<String> confirmed) async {
    await _api.post('/v1/live/agreement', {'version': version, 'confirmed': confirmed});
  }
}
