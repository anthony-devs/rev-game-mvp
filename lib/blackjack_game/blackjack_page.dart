import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../core/api/api_client.dart';
import '../games/game_support.dart';
import '../rounds/rounds_sheet.dart';
import '../model/model.dart';
import '../user/bloc/profile_cubit.dart';
import 'blackjack_api.dart';
import '../pages/how_to_play_page.dart';

/// G3. Blackjack. The deck is shuffled and played on the server.
class BlackjackPage extends StatefulWidget {
  const BlackjackPage({super.key, this.info});

  final GameInfo? info;

  @override
  State<BlackjackPage> createState() => _BlackjackPageState();
}

class _BlackjackPageState extends State<BlackjackPage> with GameSessionMixin<BlackjackPage> {
  @override
  GameType get guideType => GameType.blackjack;

  static const _chips = <double>[10, 50, 100, 500, 1000];

  late final BlackjackApi _api;

  double _bet = 100;
  BjState? _hand;
  bool _busy = false;
  bool _loading = false; // the table shows at once; resuming an open hand happens behind it
  bool _resuming = true;

  double get _minBet => widget.info?.minBet ?? 10;
  double get _maxBet => maxBetFor(widget.info?.maxBet ?? 100000);
  bool get _playing => _hand?.playing == true;
  BjResult? get _result => _hand?.result;

  @override
  void initState() {
    super.initState();
    _api = BlackjackApi(context.read<ApiClient>());
    _bet = _bet.clamp(_minBet, _maxBet).toDouble();
    _resume();
  }

  /// Pick up a hand left open (app closed mid-hand).
  Future<void> _resume() async {
    try {
      final s = await _api.active();
      if (!mounted) return;
      if (s != null) {
        holdBalance(s.balance);
        setState(() => _hand = s);
        _release(s.balance);
      }
    } catch (_) {}
    _resuming = false;
    if (mounted) setState(() {});
  }

  Future<void> _release(double expected) async {
    for (var i = 0; i < 30; i++) {
      if (!mounted) return;
      if ((walletBalance - expected).abs() < .005) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (mounted && !_busy) releaseBalance();
  }

  // ------------------------------------------------------------------ actions

  Future<void> _deal() async {
    if (_busy || _playing || _resuming) return;
    if (!checkCanPlay()) return;
    if (_bet > walletBalance) {
      showNoCredits(context, needed: _bet);
      return;
    }
    setState(() => _busy = true);
    holdBalance(walletBalance - _bet);
    AppSound.play(Sfx.card);
    AppHaptics.light();
    try {
      final s = await _api.deal(_bet);
      _apply(s, dealt: true);
    } on BjResume catch (r) {
      _apply(r.state);
      if (mounted) showToast(context, 'You still have a hand in play. Finish it first.');
    } catch (e) {
      releaseBalance();
      AppSound.play(Sfx.error);
      if (!mounted) return;
      setState(() => _busy = false);
      if (failKind(e) == FailKind.noRounds) {
      showRoundsSheet(context);
    } else if (failKind(e) == FailKind.noCredits) {
        showNoCredits(context, needed: _bet);
      } else {
        showToast(context, failText(e), error: true);
      }
    }
  }

  Future<void> _act(String action) async {
    final h = _hand;
    if (_busy || h == null || !h.playing) return;
    final extra = h.hands.isEmpty ? h.bet : h.hands[h.active.clamp(0, h.hands.length - 1)].bet;
    final costs = action == 'double' || action == 'split';
    if (costs && extra > walletBalance) {
      showNoCredits(context, needed: extra);
      return;
    }
    setState(() => _busy = true);
    if (costs) holdBalance(walletBalance - extra);
    AppSound.play(action == 'stand' ? Sfx.cardFlip : Sfx.card);
    AppHaptics.selection();
    try {
      final s = await _api.act(h.roundId, action);
      _apply(s);
    } catch (e) {
      if (costs) releaseBalance();
      AppSound.play(Sfx.error);
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, failText(e), error: true);
    }
  }

  /// A greyed-out Double or Split still answers a tap: it says why.
  void _why(String action, BjState? h) {
    if (h == null || !mounted) return;
    final cost = h.hands.isEmpty ? h.bet : h.hands[h.active.clamp(0, h.hands.length - 1)].bet;
    String msg;
    if (action == 'split') {
      final pair = h.hands.length == 1 && h.player.length == 2 && h.player[0].substring(0, h.player[0].length - 1) == h.player[1].substring(0, h.player[1].length - 1);
      msg = h.split ? 'You can split once per hand.' : (!pair ? 'Split is for two cards of the same rank, as your first move.' : 'Not enough balance to split.');
    } else {
      msg = h.player.length != 2 ? 'You can only double on your first two cards.' : (walletBalance < cost ? 'Not enough balance to double.' : 'You cannot double this hand.');
    }
    showToast(context, msg);
  }

  void _apply(BjState s, {bool dealt = false}) {
    if (!mounted) return;
    setState(() {
      _hand = s;
      _busy = false;
    });
    holdBalance(s.balance);
    final r = s.result;
    if (r != null) {
      reportRound(bet: s.bet, payout: r.payout);
      switch (r.outcome) {
        case 'blackjack':
          AppSound.play(Sfx.blackjack);
          AppHaptics.medium();
        case 'win':
          AppSound.play(Sfx.win);
          AppHaptics.medium();
        case 'push':
          AppSound.play(Sfx.cardFlip);
        default:
          AppSound.play(Sfx.lose);
      }
      _release(s.balance);
    }
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final balance = watchBalance(context);
    final h = _hand;
    final r = _result;
    final tone = r == null ? AppColors.purple : (r.isWin ? AppColors.green : (r.isPush ? AppColors.gold : AppColors.loss));

    return GameScaffold(
      title: 'Blackjack',
      balance: balance,
      lowBalance: walletBalance < _minBet && !_playing && !_busy,
      glowColor: tone,
      onHelp: () => openGuide(context, GameType.blackjack),
      onVerify: () => openFairness(context, roundId: r != null ? h?.roundId : null),
      banner: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: AppColors.surfaceAlt,
        alignment: Alignment.center,
        child: Text('BLACKJACK PAYS 3 TO 2  ·  DEALER STANDS ON 17', style: AppText.label(color: AppColors.gold, size: 10)),
      ),
      stage: _loading
          ? Center(child: AppLoader())
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _hand_('DEALER', h?.dealer ?? const [], h == null ? null : h.dealerTotal, hideTotalSuffix: _playing),
                const SizedBox(height: 22),
                _betLine(h),
                const SizedBox(height: 22),
                if (h != null && h.split) _splitHands(h) else _hand_('YOU', h?.player ?? const [], h?.playerTotal, bust: (h?.playerTotal ?? 0) > 21),
              ],
            ),
      panel: _panel(h, r, tone),
    );
  }

  Widget _betLine(BjState? h) {
    final bet = h == null ? _bet : h.bet;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('BET  ', style: AppText.label()),
        Text(formatCredits(bet, decimals: 0), style: AppText.number(14, color: AppColors.gold)),
      ]),
    );
  }

  Widget _hand_(String who, List<String> cards, int? total, {bool bust = false, bool hideTotalSuffix = false}) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(who, style: AppText.label()),
            if (total != null && cards.isNotEmpty) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(color: bust ? AppColors.loss : AppColors.surfaceAlt, borderRadius: BorderRadius.circular(12)),
                child: Text(hideTotalSuffix ? '$total+' : (bust ? '$total BUST' : '$total'), style: AppText.number(13, color: bust ? Colors.white : AppColors.text)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 108,
          child: cards.isEmpty
              ? Center(child: Text('Place a bet and deal', style: AppText.body(12, color: AppColors.textFaint)))
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < cards.length; i++)
                    Padding(
                      key: ValueKey('${_hand?.roundId}_${who}_${cards[i]}'),
                      padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                      child: _card(cards[i], order: i),
                    ),
                ]),
        ),
      ],
    );
  }

  /// Two hands after a split. The hand being played is highlighted.
  Widget _splitHands(BjState h) {
    final over = !h.playing;
    return Column(
      children: [
        Text('YOU', style: AppText.label()),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < h.hands.length; i++) ...[
              if (i > 0) const SizedBox(width: 14),
              Flexible(child: _splitHand(i, h.hands[i], current: !over && i == h.active, over: over)),
            ],
          ],
        ),
      ],
    );
  }

  Widget _splitHand(int index, BjHand hand, {required bool current, required bool over}) {
    final o = hand.outcome;
    final tone = !over ? (current ? AppColors.green : AppColors.line) : (o == 'win' ? AppColors.green : (o == 'push' ? AppColors.gold : AppColors.loss));
    final tag = over ? (o == 'win' ? '${hand.total} WON' : (o == 'push' ? '${hand.total} PUSH' : (hand.bust ? '${hand.total} BUST' : '${hand.total} LOST'))) : (hand.bust ? '${hand.total} BUST' : '${hand.total}');
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      decoration: BoxDecoration(
        color: current ? AppColors.green.withValues(alpha: .08) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tone.withValues(alpha: current || over ? .8 : 1), width: current ? 1.6 : 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tag, style: AppText.number(12, color: over || hand.bust ? tone : AppColors.text)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < hand.cards.length; i++)
                Padding(key: ValueKey('${_hand?.roundId}_s${index}_${hand.cards[i]}'), padding: EdgeInsets.only(left: i == 0 ? 0 : 5), child: _card(hand.cards[i], width: 46, order: i)),
            ]),
          ),
          const SizedBox(height: 6),
          Text(formatCredits(hand.bet, decimals: 0), style: AppText.body(11, weight: FontWeight.w700, color: AppColors.gold)),
        ],
      ),
    );
  }

  Widget _card(String c, {double width = 66, int order = 0}) => _Dealt(order: order, child: _face(c, width));

  Widget _face(String c, double width) {
    if (c == '??') return PlayingCardView(rank: 'A', suit: CardSuit.spades, faceDown: true, width: width);
    final rank = c.substring(0, c.length - 1);
    final suit = switch (c[c.length - 1]) {
      'S' => CardSuit.spades,
      'H' => CardSuit.hearts,
      'D' => CardSuit.diamonds,
      _ => CardSuit.clubs,
    };
    return PlayingCardView(rank: rank, suit: suit, width: width);
  }

  Widget _panel(BjState? h, BjResult? r, Color tone) {
    Widget body;
    if (_playing) {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: AppButton(label: 'HIT', variant: AppButtonVariant.success, height: 58, cooldown: Duration.zero, loading: _busy, onPressed: _busy ? null : () => _act('hit'))),
          const SizedBox(width: 10),
          Expanded(child: AppButton(label: 'STAND', variant: AppButtonVariant.outline, height: 58, cooldown: Duration.zero, onPressed: _busy ? null : () => _act('stand'))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: AppButton(label: 'Double', variant: AppButtonVariant.outline, height: 46, fontSize: 13, cooldown: Duration.zero, onDisabledTap: _busy ? null : () => _why('double', h), onPressed: _busy || h?.canDouble != true ? null : () => _act('double'))),
          const SizedBox(width: 10),
          Expanded(child: AppButton(label: 'Split', variant: AppButtonVariant.outline, height: 46, fontSize: 13, cooldown: Duration.zero, onDisabledTap: _busy ? null : () => _why('split', h), onPressed: _busy || h?.canSplit != true ? null : () => _act('split'))),
        ]),
      ]);
    } else if (r != null && h != null) {
      final stake = h.bet;
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.isWin ? 'YOU WON' : (r.isPush ? 'PUSH' : 'DEALER WINS'), style: AppText.label(color: tone)),
              const SizedBox(height: 2),
              Text(r.label.isEmpty ? _outcomeText(r, stake) : r.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.body(12, color: AppColors.textMuted)),
            ]),
          ),
          Text(formatSigned(r.net), style: AppText.number(26, color: tone, shadows: r.isWin ? AppText.glow(tone, opacity: .4) : null)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: AppButton(label: 'Change bet', variant: AppButtonVariant.outline, height: 56, fontSize: 15, onPressed: () => setState(() {
                _hand = null;
              }))),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: AppButton(label: 'DEAL AGAIN', variant: AppButtonVariant.success, height: 56, fontSize: 15, loading: _busy, onPressed: _busy ? null : () {
                setState(() => _hand = null);
                _deal();
              })),
        ]),
        const SizedBox(height: 6),
        PressScale(
          onTap: () => openFairness(context, roundId: h.roundId),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Verify this round', style: AppText.body(13, weight: FontWeight.w600, color: AppColors.green, decoration: TextDecoration.underline)),
          ),
        ),
      ]);
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        BetChipPicker(values: _chips, selected: _bet, size: 54, onSelected: (v) {
          AppSound.play(Sfx.chip);
          setState(() => _bet = v.clamp(_minBet, _maxBet).toDouble());
        }),
        const SizedBox(height: 14),
        AppButton(label: 'DEAL', sublabel: 'BET ${formatCredits(_bet, decimals: 0)}', variant: AppButtonVariant.success, height: 64, loading: _busy || _resuming, onPressed: _busy || _resuming ? null : _deal),
      ]);
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppColors.sheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: AnimatedSize(duration: const Duration(milliseconds: 180), alignment: Alignment.topCenter, child: body),
    );
  }

  String _outcomeText(BjResult r, double stake) => switch (r.outcome) {
        'blackjack' => 'Blackjack, pays 3 to 2 on ${formatCredits(stake, decimals: 0)}',
        'win' => 'Hand won',
        'push' => 'Bet returned',
        'bust' => 'Bust',
        _ => 'Hand lost',
      };
}

/// A card slides in from above and settles with a small bounce. Cards already on the table keep
/// their place (they are keyed), so only the new card moves.
class _Dealt extends StatelessWidget {
  const _Dealt({required this.child, this.order = 0});

  final Widget child;
  final int order;

  @override
  Widget build(BuildContext context) {
    final lead = (order * 110).clamp(0, 440);
    final total = 280 + lead;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(lead / total, 1, curve: Curves.easeOutBack),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, -34 * (1 - t)), child: Transform.scale(scale: .86 + .14 * t, child: child)),
      ),
      child: child,
    );
  }
}
