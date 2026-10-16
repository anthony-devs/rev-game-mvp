import '../../core/api/api_client.dart';
import '../../model/model_json.dart';

/// Result of a daily claim.
class DailyClaim {
  const DailyClaim({required this.claimed, required this.streakDays, required this.balance});
  final double claimed;
  final int streakDays;
  final double balance;
}

/// A seed pair as shown on the Fairness screen.
class FairnessState {
  const FairnessState({required this.serverSeedHash, required this.clientSeed, required this.nonce});
  final String serverSeedHash;
  final String clientSeed;
  final int nonce;

  factory FairnessState.fromJson(Json j) => FairnessState(
        serverSeedHash: parseString(j['serverSeedHash']) ?? '',
        clientSeed: parseString(j['clientSeed']) ?? '',
        nonce: parseInt(j['nonce']),
      );
}

class RevealedSeed {
  const RevealedSeed({required this.serverSeed, required this.serverSeedHash, required this.nonceEnd});
  final String serverSeed;
  final String serverSeedHash;
  final int nonceEnd;
}

class RotateResult {
  const RotateResult({required this.current, this.revealed});
  final FairnessState current;
  final RevealedSeed? revealed;
}

/// `verified`, `pending` (seed not revealed yet) or `mismatch`.
class VerifyResult {
  const VerifyResult({
    required this.status,
    required this.game,
    required this.serverSeedHash,
    required this.clientSeed,
    required this.nonce,
    this.serverSeed,
    this.hashMatches,
    this.outcomeMatches,
  });

  final String status;
  final String game;
  final String serverSeedHash;
  final String clientSeed;
  final int nonce;
  final String? serverSeed;
  final bool? hashMatches;
  final bool? outcomeMatches;

  bool get isVerified => status == 'verified';
  bool get isPending => status == 'pending';

  factory VerifyResult.fromJson(Json j) => VerifyResult(
        status: parseString(j['status']) ?? 'pending',
        game: parseString(j['game']) ?? '',
        serverSeedHash: parseString(j['serverSeedHash']) ?? '',
        clientSeed: parseString(j['clientSeed']) ?? '',
        nonce: parseInt(j['nonce']),
        serverSeed: parseString(j['serverSeed']),
        hashMatches: j['hashMatches'] is bool ? j['hashMatches'] as bool : null,
        outcomeMatches: j['outcomeMatches'] is bool ? j['outcomeMatches'] as bool : null,
      );
}

/// Wallet, fairness and account actions that only the game server may perform.
class WalletApi {
  WalletApi(this._api);

  final ApiClient _api;

  /// Throws [ApiException] (code `daily_not_ready` when too early).
  Future<DailyClaim> claimDaily() async {
    final j = await _api.post('/v1/wallet/claim-daily');
    return DailyClaim(
      claimed: parseDouble(j['claimed']),
      streakDays: parseInt(j['streakDays']),
      balance: parseDouble(j['balance']),
    );
  }

  /// Refills to the starting balance when the player is below it.
  Future<double> topUp() async {
    final j = await _api.post('/v1/wallet/top-up');
    return parseDouble(j['balance']);
  }

  /// Back to the starting balance (history and level stay).
  Future<double> reset() async {
    final j = await _api.post('/v1/wallet/reset');
    return parseDouble(j['balance']);
  }

  /// Asks the server to settle any suspension or probation that has ended.
  /// The result arrives through the live Firestore listener.
  Future<void> refreshStanding() async {
    await _api.get('/v1/account/standing');
  }

  /// Appeal an active ban, suspension, restriction or investigation.
  /// [attachments] are ids from `SupportApi.upload` (photos, videos, PDFs).
  Future<void> appeal(String actionId, String message, {List<String> attachments = const []}) async {
    await _api.post('/v1/account/appeal', {'actionId': actionId, 'message': message, 'attachments': attachments});
  }

  Future<FairnessState> fairness() async => FairnessState.fromJson(await _api.get('/v1/fairness'));

  Future<RotateResult> rotateSeed({String? clientSeed}) async {
    final j = await _api.post('/v1/fairness/rotate', {if (clientSeed != null) 'clientSeed': clientSeed});
    final r = parseMap(j['revealed']);
    return RotateResult(
      current: FairnessState.fromJson(parseMap(j['current'])),
      revealed: r.isEmpty
          ? null
          : RevealedSeed(
              serverSeed: parseString(r['serverSeed']) ?? '',
              serverSeedHash: parseString(r['serverSeedHash']) ?? '',
              nonceEnd: parseInt(r['nonceEnd']),
            ),
    );
  }

  Future<VerifyResult> verify(String roundId) async =>
      VerifyResult.fromJson(await _api.get('/v1/fairness/verify/$roundId'));

  /// Deletes all data and the sign-in account. The caller then signs out.
  Future<void> deleteAccount() async {
    await _api.delete('/v1/account');
  }
}
