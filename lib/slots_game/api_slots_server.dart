import '../core/api/api_client.dart';
import '../model/model_json.dart';
import 'slots_models.dart';
import 'slots_server.dart';

/// Slots backed by the real game server.
class ApiSlotsServer implements SlotsServer {
  ApiSlotsServer(this._api, {this.game = 'slots'});

  final ApiClient _api;

  /// Which machine: slots (Golden Reels), or lucky7.
  @override
  final String game;

  /// The last config the server sent for each machine. A machine opens with this at once and refreshes it quietly.
  static final Map<String, SlotsConfig> _cache = {};
  static SlotsConfig? cachedFor(String game) => _cache[game];
  static void clearCache() => _cache.clear();

  /// Fetch the config ahead of time (after sign in), so the game doesn't open on a spinner.
  static Future<void> prefetch(ApiClient api) async {
    try {
      await ApiSlotsServer(api).fetchConfig();
    } catch (_) {}
  }

  @override
  Future<SlotsConfig> fetchConfig() async {
    final j = await _api.get('/v1/slots/config?game=$game');
    final cfg = SlotsConfig(
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
      pairSymbol: _pair(j['payRows']),
    );
    _cache[game] = cfg;
    return cfg;
  }

  /// A pay row with two symbols is the "any 2" row. Its symbol is the one that pays on two.
  SlotSymbol? _pair(Object? rows) {
    for (final r in (rows as List? ?? const [])) {
      final syms = parseMap(r)['symbols'] as List? ?? const [];
      if (syms.length == 2) return _symbol(syms.first);
    }
    return null;
  }

  @override
  Future<SpinResult> spin(double bet) async {
    final j = await _api.post('/v1/slots/spin', {'bet': bet, 'game': game});
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
