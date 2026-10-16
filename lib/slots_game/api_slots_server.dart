import '../core/api/api_client.dart';
import '../model/model_json.dart';
import 'slots_models.dart';
import 'slots_server.dart';

/// Slots backed by the real game server.
class ApiSlotsServer implements SlotsServer {
  ApiSlotsServer(this._api);

  final ApiClient _api;

  @override
  Future<SlotsConfig> fetchConfig() async {
    final j = await _api.get('/v1/slots/config');
    return SlotsConfig(
      minBet: parseDouble(j['minBet']),
      maxBet: parseDouble(j['maxBet']),
      betSteps: [for (final s in (j['betSteps'] as List? ?? const [])) parseDouble(s)],
      defaultBet: parseDouble(j['defaultBet']),
      startBalance: parseDouble(j['startBalance']),
      bigWinMultiplier: parseInt(j['bigWinMultiplier'], 50),
      rtp: parseDouble(j['rtp']),
      payRows: [
        for (final r in (j['payRows'] as List? ?? const []))
          PayRow(
            [for (final s in (parseMap(r)['symbols'] as List? ?? const [])) _symbol(s)],
            parseString(parseMap(r)['label']) ?? '',
            parseInt(parseMap(r)['multiplier']),
            0,
          ),
      ],
    );
  }

  @override
  Future<SpinResult> spin(double bet) async {
    final j = await _api.post('/v1/slots/spin', {'bet': bet});
    return SpinResult(
      columns: [
        for (final col in (j['columns'] as List? ?? const []))
          [for (final s in (col as List)) _symbol(s)],
      ],
      multiplier: parseInt(j['multiplier']),
      payout: parseDouble(j['payout']),
      balanceAfterBet: parseDouble(j['balanceAfterBet']),
      balanceAfter: parseDouble(j['balance']),
      label: parseString(j['label']) ?? '',
      roundId: parseString(j['roundId']) ?? '',
    );
  }

  SlotSymbol _symbol(Object? name) => enumByName(SlotSymbol.values, name, SlotSymbol.cherry);
}
