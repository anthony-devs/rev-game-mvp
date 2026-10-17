import '../core/api/api_client.dart';
import '../model/model_json.dart';

class BjResult {
  const BjResult({required this.outcome, required this.payout, required this.net, required this.label});

  /// blackjack, win, push, lose or bust.
  final String outcome;
  final double payout;
  final double net;
  final String label;

  bool get isWin => outcome == 'blackjack' || outcome == 'win';
  bool get isPush => outcome == 'push';

  factory BjResult.fromJson(Map<String, dynamic> j) => BjResult(
        outcome: parseString(j['outcome']) ?? 'lose',
        payout: parseDouble(j['payout']),
        net: parseDouble(j['net']),
        label: parseString(j['label']) ?? '',
      );
}

/// One of the player's hands (two after a split).
class BjHand {
  const BjHand({required this.cards, required this.total, required this.bet, required this.doubled, this.outcome});

  final List<String> cards;
  final int total;
  final double bet;
  final bool doubled;

  /// win, push, lose or bust once the round is over.
  final String? outcome;

  bool get bust => total > 21;

  factory BjHand.fromJson(Map<String, dynamic> j) => BjHand(
        cards: [for (final c in (j['cards'] as List? ?? const [])) '$c'],
        total: parseInt(j['total']),
        bet: parseDouble(j['bet']),
        doubled: j['doubled'] == true,
        outcome: parseString(j['outcome']),
      );
}

class BjState {
  const BjState({
    required this.roundId,
    required this.playing,
    required this.bet,
    required this.player,
    required this.dealer,
    required this.playerTotal,
    required this.dealerTotal,
    required this.doubled,
    required this.canDouble,
    required this.balance,
    this.canSplit = false,
    this.split = false,
    this.active = 0,
    this.hands = const [],
    this.result,
  });

  final String roundId;
  final bool playing;
  /// Total staked on the round (both hands after a split, doubles included).
  final double bet;

  /// Cards like "AS" or "10H". The dealer's hidden card is "??".
  final List<String> player;
  final List<String> dealer;
  final int playerTotal;
  final int dealerTotal;
  final bool doubled;
  final bool canDouble;
  final bool canSplit;
  final bool split;
  final int active;
  final List<BjHand> hands;
  final double balance;
  final BjResult? result;

  factory BjState.fromJson(Map<String, dynamic> j) {
    List<String> cards(Object? v) => [for (final c in (v as List? ?? const [])) '$c'];
    final res = j['result'];
    return BjState(
      roundId: parseString(j['roundId']) ?? '',
      playing: j['status'] == 'player',
      bet: parseDouble(j['bet']),
      player: cards(j['player']),
      dealer: cards(j['dealer']),
      playerTotal: parseInt(j['playerTotal']),
      dealerTotal: parseInt(j['dealerTotal']),
      doubled: j['doubled'] == true,
      canDouble: j['canDouble'] == true,
      canSplit: j['canSplit'] == true,
      split: j['split'] == true,
      active: parseInt(j['active']),
      hands: [for (final h in (j['hands'] as List? ?? const [])) BjHand.fromJson(parseMap(h))],
      balance: parseDouble(j['balance']),
      result: res is Map ? BjResult.fromJson(parseMap(res)) : null,
    );
  }
}

/// A 409 from deal: a hand is already open. Carries that hand.
class BjResume implements Exception {
  BjResume(this.state);
  final BjState state;
}

class BlackjackApi {
  BlackjackApi(this._api);

  final ApiClient _api;

  Future<BjState?> active() async {
    final j = await _api.get('/v1/blackjack/active');
    final s = j['active'];
    return s is Map ? BjState.fromJson(parseMap(s)) : null;
  }

  Future<BjState> deal(double bet) async {
    try {
      return BjState.fromJson(await _api.post('/v1/blackjack/deal', {'bet': bet}));
    } on ApiException catch (e) {
      final s = e.data['state'];
      if (e.code == 'round_in_progress' && s is Map) throw BjResume(BjState.fromJson(parseMap(s)));
      rethrow;
    }
  }

  Future<BjState> act(String roundId, String action) async =>
      BjState.fromJson(await _api.post('/v1/blackjack/$roundId/$action', const {}));
}
