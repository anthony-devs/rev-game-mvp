import '../core/api/api_client.dart';
import '../model/model_json.dart';

class ReferralInfo {
  const ReferralInfo({
    required this.enabled,
    required this.code,
    required this.link,
    required this.friendRounds,
    required this.referrerRounds,
    required this.qualifyRounds,
    required this.maxRewards,
    required this.invited,
    required this.rewarded,
    required this.roundsEarned,
    required this.canApply,
    this.boostMult,
    this.boostSecondsLeft = 0,
  });

  final bool enabled;
  final String code;
  final String link;
  final int friendRounds;
  final int referrerRounds;
  final int qualifyRounds;
  final int maxRewards;
  final int invited;
  final int rewarded;
  final int roundsEarned;
  final bool canApply;
  final double? boostMult;
  final int boostSecondsLeft;

  factory ReferralInfo.fromJson(Map<String, dynamic> j) {
    final b = j['boost'];
    return ReferralInfo(
      enabled: j['enabled'] != false,
      code: parseString(j['code']) ?? '',
      link: parseString(j['link']) ?? '',
      friendRounds: parseInt(j['friendRounds']),
      referrerRounds: parseInt(j['referrerRounds']),
      qualifyRounds: parseInt(j['qualifyRounds']),
      maxRewards: parseInt(j['maxRewards']),
      invited: parseInt(j['invited']),
      rewarded: parseInt(j['rewarded']),
      roundsEarned: parseInt(j['roundsEarned']),
      canApply: j['canApply'] == true,
      boostMult: b is Map ? parseDouble(b['mult']) : null,
      boostSecondsLeft: b is Map ? parseInt(b['secondsLeft']) : 0,
    );
  }
}

class ReferralApi {
  ReferralApi(this._api);

  final ApiClient _api;

  Future<ReferralInfo> info() async => ReferralInfo.fromJson(await _api.get('/v1/referral'));

  /// Adds a friend's code. Returns how many bonus rounds were added.
  Future<int> apply(String code) async {
    final j = await _api.post('/v1/referral/apply', {'code': code});
    return parseInt(j['rounds']);
  }
}
