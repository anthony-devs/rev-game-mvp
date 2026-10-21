import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../games/game_support.dart';
import '../model/model.dart';
import 'game_detail_page.dart';
import 'round_format.dart';
import '../user/bloc/profile_cubit.dart';

class _Step {
  const _Step(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

class _Guide {
  const _Guide({required this.name, required this.accent, required this.intro, required this.steps, this.reference = const [], this.tip});
  final String name;
  final Color accent;
  final String intro;
  final List<_Step> steps;

  /// Label / value rows shown on the last page (payouts, card values...).
  final List<(String, String)> reference;
  final String? tip;
}

const _credits = _Step(Icons.verified_user_outlined, 'Provably fair', 'Every result is generated fairly, and you can verify any round yourself in Provably fair.');

_Guide _guideFor(GameType t) {
  switch (t) {
    case GameType.roulette:
      return _Guide(
        name: 'Roulette',
        accent: AppColors.green,
        intro: 'A ball lands on one of 37 pockets, numbered 0 to 36. You bet on where it will land.',
        steps: [
          _Step(Icons.paid_rounded, 'Pick a chip', 'Choose a chip value at the bottom: 10, 50, 100, 500 or 1K. Every tap on the table places one chip of that value.'),
          _Step(Icons.grid_view_rounded, 'Place your bets', 'Tap a number for a single-number bet, or tap a section: a dozen, Red or Black, Odd or Even, 1-18 or 19-36. You can place as many bets as you like. Undo removes the last chip and Clear removes all.'),
          _Step(Icons.rotate_right_rounded, 'Spin', 'Press SPIN. The result is decided on the server, then the wheel shows where the ball landed.'),
          _Step(Icons.emoji_events_rounded, 'Get paid', 'Each winning bet pays at its rate (see the table next). Losing bets are gone. Rebet and Spin repeats your last round in one tap.'),
        ],
        reference: [
          ('A single number', 'pays 35 to 1'),
          ('1st / 2nd / 3rd 12', 'pays 2 to 1'),
          ('Red, Black, Odd, Even, 1-18, 19-36', 'pays 1 to 1'),
          ('Zero (0)', 'beats every outside bet'),
        ],
        tip: 'Red/Black and the other 1-to-1 bets win almost half the time. A single number is rare but pays the most.',
      );
    case GameType.blackjack:
      return _Guide(
        name: 'Blackjack',
        accent: AppColors.purple,
        intro: 'Get a hand closer to 21 than the dealer, without going over.',
        steps: [
          _Step(Icons.paid_rounded, 'Bet and deal', 'Choose your bet and press DEAL. You get two cards. The dealer shows one and hides the other.'),
          _Step(Icons.style_rounded, 'Count your cards', '2 to 10 are worth their number. J, Q and K are worth 10. An Ace is worth 11, or 1 if 11 would put you over 21.'),
          _Step(Icons.touch_app_rounded, 'Hit, Stand or Double', 'HIT takes another card. STAND keeps your hand. DOUBLE doubles your bet, gives you exactly one more card, then you stand. Double is only available on your first move.'),
          _Step(Icons.person_rounded, 'The dealer plays', 'After you stand, the dealer reveals the hidden card and draws until reaching 17 or more. The dealer stands on every 17.'),
          _Step(Icons.emoji_events_rounded, 'Who wins', 'Closer to 21 wins. Go over 21 and you bust and lose at once. A tie is a push and your bet comes back.'),
        ],
        reference: [
          ('Blackjack (Ace + 10 on the first two cards)', 'pays 3 to 2'),
          ('Regular win', 'pays 1 to 1'),
          ('Push (tie)', 'bet returned'),
          ('Bust (over 21)', 'bet lost'),
        ],
        tip: 'Split a pair of the same rank once, as your first move. It needs a second bet equal to your first. Split aces get one card each. Insurance is not offered.',
      );
    case GameType.dice:
      return _Guide(
        name: 'Dice',
        accent: AppColors.blue,
        intro: 'A number from 0.00 to 99.99 is rolled. You bet on whether it lands over or under your target.',
        steps: [
          _Step(Icons.tune_rounded, 'Set your target', 'Drag the slider to choose a target number.'),
          _Step(Icons.swap_vert_rounded, 'Over or Under', 'Choose Under to win when the roll is below your target, or Over to win when it is above.'),
          _Step(Icons.percent_rounded, 'Chance vs. reward', 'The less likely your bet, the bigger the multiplier. The screen shows your win chance and your multiplier before you roll.'),
          _Step(Icons.casino_rounded, 'Roll', 'Set your bet and press ROLL. If the result is on the right side of your target, you win bet × multiplier.'),
        ],
        tip: 'A high win chance gives small, frequent wins. A low win chance gives big, rare ones.',
      );
    case GameType.plinko:
      return _Guide(
        name: 'Plinko',
        accent: AppColors.mint,
        intro: 'Drop a ball through rows of pegs. It lands in a slot, and each slot pays a multiplier on your bet.',
        steps: [
          _Step(Icons.tune_rounded, 'Choose risk and rows', 'Low risk pays small, steady multipliers. High risk pays huge multipliers at the edges and little in the middle. More rows add slots and make the edges bigger.'),
          _Step(Icons.paid_rounded, 'Set your bet', 'The highest bet allowed depends on the board you chose, because the biggest multiplier is capped by a payout limit.'),
          _Step(Icons.arrow_downward_rounded, 'Drop the ball', 'Press DROP. The result is decided on the server first, then you watch the ball fall to its slot.'),
          _Step(Icons.emoji_events_rounded, 'Get paid', 'You receive your bet times the multiplier of the slot where the ball lands. Under 1x returns part of your bet.'),
        ],
        tip: 'The middle slots are the most likely. Each drop is independent, and any round can be verified with the shield icon.',
      );
    case GameType.crash:
      return _Guide(
        name: 'Dash Crash',
        accent: AppColors.gold,
        intro: 'A multiplier climbs from 1.00x. Cash out before it crashes.',
        steps: [
          _Step(Icons.paid_rounded, 'Place your bet', 'Choose your bet before the round starts and press the bet button.'),
          _Step(Icons.trending_up_rounded, 'Watch it climb', 'The character runs and the multiplier rises. Your possible payout is your bet × the current multiplier.'),
          _Step(Icons.back_hand_rounded, 'Cash out in time', 'Press CASH OUT at any moment to lock in the current multiplier. If it crashes first, you lose the bet.'),
          _Step(Icons.flag_rounded, 'Auto cash-out', 'Set a target multiplier and the game cashes out for you when it is reached. Auto-bet repeats your bet each round.'),
        ],
        tip: 'Nobody can predict the crash point, and it is decided before the round starts. Verify any round with the shield icon.',
      );
    case GameType.mines:
      return _Guide(
        name: 'Mines',
        accent: AppColors.mint,
        intro: 'A 5 by 5 board hides mines. Open tiles to raise your multiplier and cash out before you hit one.',
        steps: [
          _Step(Icons.tune_rounded, 'Choose your mines', 'Pick how many mines hide on the board, from 1 to 24. More mines means a bigger reward for every safe tile, and a bigger risk.'),
          _Step(Icons.paid_rounded, 'Set your bet and start', 'Choose your bet and press START. The mines are placed on the server before you open anything.'),
          _Step(Icons.touch_app_rounded, 'Open tiles', 'Tap a tile. A gem is safe and raises your multiplier. A mine ends the round and the bet is lost.'),
          _Step(Icons.emoji_events_rounded, 'Cash out', 'Press CASH OUT at any moment to collect your bet times the current multiplier. Clear the whole board and it pays out for you.'),
        ],
        tip: 'The multiplier for your next tile is shown on screen. Every round can be verified with the shield icon once it is over.',
      );
    case GameType.baccarat:
      return _Guide(
        name: 'Baccarat',
        accent: AppColors.purple,
        intro: 'Two hands are dealt, the Player and the Banker. The hand closest to 9 wins.',
        steps: [
          _Step(Icons.paid_rounded, 'Place your bet', 'Pick a chip and tap Player, Banker or Tie. You can bet on more than one.'),
          _Step(Icons.style_rounded, 'Card values', 'Aces are worth 1. 2 to 9 are worth their number. 10, J, Q and K are worth 0. Only the last digit of a total counts, so 7 + 8 = 15 is a 5.'),
          _Step(Icons.sync_rounded, 'Deal', 'Press DEAL. Each side gets two cards. A third card is drawn automatically by the standard rules. A total of 8 or 9 on the first two cards is a natural and stops the draw.'),
          _Step(Icons.emoji_events_rounded, 'Get paid', 'The closest hand to 9 wins. If both are equal it is a Tie.'),
        ],
        reference: [
          ('Player', 'pays 1 to 1'),
          ('Banker', 'pays 1 to 1, less 5% commission'),
          ('Tie', 'pays 8 to 1'),
          ('Tie round', 'Player and Banker bets are returned'),
        ],
        tip: 'Banker wins slightly more often than Player, which is why it carries a commission.',
      );
    case GameType.wheel:
      return _Guide(
        name: 'Lucky Wheel',
        accent: AppColors.gold,
        intro: 'Spin a wheel of 20 segments. The segment it stops on pays its multiplier.',
        steps: [
          _Step(Icons.tune_rounded, 'Choose a risk level', 'Low has many small wins. Medium is balanced. High has mostly empty segments and a few big prizes.'),
          _Step(Icons.paid_rounded, 'Set your bet', 'Choose your bet with the chips.'),
          _Step(Icons.rotate_right_rounded, 'Spin', 'Press SPIN. The result is decided on the server first, then the wheel shows where it stopped.'),
          _Step(Icons.emoji_events_rounded, 'Get paid', 'You receive your bet times the multiplier of the segment. A segment under 1x returns part of your bet, and 0x pays nothing.'),
        ],
        tip: 'Every segment is equally likely. Any round can be verified with the shield icon.',
      );
    case GameType.keno:
      return _Guide(
        name: 'Keno',
        accent: AppColors.blue,
        intro: 'Pick your numbers, then ten numbers are drawn. Match as many as you can.',
        steps: [
          _Step(Icons.grid_view_rounded, 'Pick numbers', 'Tap 1 to 10 numbers on the board of 40. Tap again to remove one. Auto picks random numbers for you.'),
          _Step(Icons.paid_rounded, 'Set your bet', 'The pay table for your number of picks is shown under the board.'),
          _Step(Icons.sync_rounded, 'Play', 'Press PLAY. Ten numbers are drawn on the server and your matches light up.'),
          _Step(Icons.emoji_events_rounded, 'Get paid', 'Your bet times the multiplier for the number of matches you got.'),
        ],
        tip: 'Fewer picks win more often. More picks pay far more when most of them hit.',
      );
    case GameType.hilo:
      return _Guide(
        name: 'Hi-Lo',
        accent: AppColors.mint,
        intro: 'Guess whether the next card is higher or lower than the one showing, and build a streak.',
        steps: [
          _Step(Icons.paid_rounded, 'Bet and start', 'Choose your bet and press START. A card is shown.'),
          _Step(Icons.swap_vert_rounded, 'Higher or Lower', 'Aces are low and kings are high. The same rank counts as a win for both guesses. Each button shows its chance and the multiplier you would reach.'),
          _Step(Icons.trending_up_rounded, 'Build a streak', 'Each right guess multiplies your multiplier. A less likely guess pays more.'),
          _Step(Icons.back_hand_rounded, 'Cash out', 'Press CASH OUT any time after a right guess to collect your bet times the multiplier. A wrong guess loses the bet.'),
        ],
        tip: 'The deck is shuffled once, so the chances are exact and change as cards are used. Verify any round with the shield icon.',
      );
    case GameType.slots:
      return _Guide(
        name: 'Slots',
        accent: AppColors.gold,
        intro: 'Spin the reels and line up matching symbols.',
        steps: [
          _Step(Icons.paid_rounded, 'Choose your bet', 'Use the bet buttons to raise or lower your stake for each spin.'),
          _Step(Icons.sync_rounded, 'Spin', 'Press SPIN. The reels stop one by one. Turbo makes the spin faster.'),
          _Step(Icons.view_week_rounded, 'Match symbols', 'Matching symbols on a payline win. Rarer symbols pay more.'),
          _Step(Icons.info_outline_rounded, 'Check the paytable', 'Tap the info icon to see what each symbol pays.'),
        ],
        tip: 'Wins are shown with a highlight on the winning symbols. Bigger wins get a celebration.',
      );
    default:
      final climb = const {GameType.tower, GameType.chicken, GameType.pump, GameType.moles}.contains(t);
      return _Guide(
        name: t.title,
        accent: GameArtStyle.accentOf(t.kind),
        intro: GameDetailPage.howTo(t),
        steps: climb
            ? const [
                _Step(Icons.tune_rounded, 'Pick a difficulty', 'Harder levels raise the multiplier faster but make a bad move more likely.'),
                _Step(Icons.paid_rounded, 'Set your bet', 'Choose your bet with the chips and press START.'),
                _Step(Icons.trending_up_rounded, 'Climb', 'Every safe move raises your multiplier. The result of each move is decided by the server.'),
                _Step(Icons.back_hand_rounded, 'Cash out', 'Press CASH OUT any time to collect your bet times the multiplier. A bad move loses the bet.'),
              ]
            : const [
                _Step(Icons.tune_rounded, 'Make your choice', 'Pick your target, side or risk level if the game has one.'),
                _Step(Icons.paid_rounded, 'Set your bet', 'Choose your bet with the chips.'),
                _Step(Icons.play_arrow_rounded, 'Play', 'Press the big button. The result is decided on the server first, then shown.'),
                _Step(Icons.emoji_events_rounded, 'Get paid', 'A win pays your bet times the multiplier shown. Your balance updates straight away.'),
              ],
        tip: 'Every round is provably fair. Verify any round with the shield icon.',
      );
  }
}

/// Whether this player has already seen the guide for [type].
bool _seen(BuildContext context, GameType type) => context.read<ProfileCubit>().state.settings.seenGuides.contains(type.name);

/// Open the guide from a "How to play" button.
Future<void> openGuide(BuildContext context, GameType type) => pushPage<void>(context, HowToPlayPage(type: type));

/// Open the guide once, the first time a player enters a game.
Future<void> showGuideIfFirstTime(BuildContext context, GameType type) async {
  if (_seen(context, type)) return;
  final cubit = context.read<ProfileCubit>();
  final s = cubit.state.settings;
  // Mark as seen straight away, so it never nags again even if skipped.
  cubit.updateSettings(s.copyWith(seenGuides: [...s.seenGuides, type.name]));
  await openGuide(context, type);
}

/// Step-by-step "How to play" walkthrough.
class HowToPlayPage extends StatefulWidget {
  const HowToPlayPage({super.key, required this.type});

  final GameType type;

  @override
  State<HowToPlayPage> createState() => _HowToPlayPageState();
}

class _HowToPlayPageState extends State<HowToPlayPage> {
  final _pages = PageController();
  int _index = 0;

  late final _Guide _g = _guideFor(widget.type);

  // intro + steps + summary
  int get _count => _g.steps.length + 2;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_index >= _count - 1) {
      Navigator.of(context).maybePop();
      return;
    }
    AppSound.play(Sfx.tap, volume: .5);
    _pages.nextPage(duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _count - 1;
    return AppScaffold(
      glowColor: _g.accent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                IconSquareButton(icon: Icons.close_rounded, semanticLabel: 'Close', onPressed: () => Navigator.of(context).maybePop()),
                const SizedBox(width: 12),
                Expanded(child: Text('How to play ${_g.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(17, weight: FontWeight.w700))),
              ],
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: _count,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) {
                if (i == 0) return _page(Icons.menu_book_rounded, 'The idea', _g.intro, extra: _credits.body);
                if (i == _count - 1) return _summary();
                final s = _g.steps[i - 1];
                return _page(s.icon, 'Step $i  ·  ${s.title}', s.body);
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _count; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _index ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: i == _index ? _g.accent : AppColors.lineStrong),
                ),
            ],
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 18, 16, 16 + MediaQuery.of(context).padding.bottom),
            child: Row(
              children: [
                if (!last) ...[
                  Expanded(child: AppButton(label: 'Skip', variant: AppButtonVariant.outline, height: 56, fontSize: 15, onPressed: () => Navigator.of(context).maybePop())),
                  const SizedBox(width: 10),
                ],
                Expanded(flex: 2, child: AppButton(label: last ? 'GOT IT' : 'Next', variant: AppButtonVariant.success, height: 56, fontSize: 15, onPressed: _next)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _page(IconData icon, String title, String body, {String? extra}) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 8),
      children: [
        Center(
          child: Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _g.accent.withValues(alpha: .14), border: Border.all(color: _g.accent.withValues(alpha: .5), width: 2)),
            child: Icon(icon, size: 52, color: _g.accent),
          ),
        ),
        const SizedBox(height: 30),
        Text(title, textAlign: TextAlign.center, style: AppText.heading(24, letterSpacing: -.5)),
        const SizedBox(height: 14),
        Text(body, textAlign: TextAlign.center, style: AppText.body(15, color: AppColors.textMuted, height: 1.6)),
        if (extra != null) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.toll_rounded, size: 18, color: AppColors.gold),
                const SizedBox(width: 10),
                Expanded(child: Text(extra, style: AppText.body(12.5, color: AppColors.textDim, height: 1.5))),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _summary() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
      children: [
        Text('Quick reference', textAlign: TextAlign.center, style: AppText.heading(24, letterSpacing: -.5)),
        const SizedBox(height: 18),
        if (_g.reference.isNotEmpty)
          Container(
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
            child: Column(
              children: [
                for (var i = 0; i < _g.reference.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: AppColors.line),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Expanded(child: Text(_g.reference[i].$1, style: AppText.body(13.5, color: AppColors.textSoft))),
                        const SizedBox(width: 12),
                        Text(_g.reference[i].$2, textAlign: TextAlign.right, style: AppText.body(13.5, weight: FontWeight.w700, color: _g.accent)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (_g.tip != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _g.accent.withValues(alpha: .1), borderRadius: BorderRadius.circular(14), border: Border.all(color: _g.accent.withValues(alpha: .35))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline_rounded, size: 18, color: _g.accent),
                const SizedBox(width: 10),
                Expanded(child: Text(_g.tip!, style: AppText.body(13, color: AppColors.textSoft, height: 1.5))),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        Text('You can reopen this any time with the ? button at the top of the game.', textAlign: TextAlign.center, style: AppText.body(12, color: AppColors.textFaint)),
      ],
    );
  }
}
