import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../catalog/catalog_cubit.dart';
import '../catalog/server_banner.dart';
import '../games/game_launcher.dart';
import '../games/game_support.dart';
import '../model/model.dart';
import '../user/bloc/profile_cubit.dart';
import '../user/data/user_repository.dart';
import 'how_to_play_page.dart';
import 'round_format.dart';
import '../support/faq_data.dart';
import 'help_page.dart';

/// L4. Game details: limits, how it works, your last results, Play now.
class GameDetailPage extends StatelessWidget {
  const GameDetailPage({super.key, required this.game});

  final GameInfo game;

  static String _blurb(GameType t) {
    switch (t) {
      case GameType.slots:
        return 'Classic 3 reel slot with a single payline';
      case GameType.roulette:
        return 'European roulette with a single zero';
      case GameType.blackjack:
        return 'Beat the dealer to 21. Blackjack pays 3 to 2';
      case GameType.dice:
        return 'Set your odds, roll under or over';
      case GameType.crash:
        return 'Cash out before the multiplier crashes';
      case GameType.plinko:
        return 'Drop the ball and hit a big multiplier';
      case GameType.mines:
        return 'Open tiles, avoid the mines, cash out any time';
      case GameType.baccarat:
        return 'Bet on the Player, the Banker or a Tie';
      case GameType.wheel:
        return 'Spin the wheel and land on a multiplier';
      case GameType.keno:
        return 'Pick your numbers and match the draw';
      case GameType.hilo:
        return 'Guess higher or lower and build a streak';
      default:
        return const {GameType.limbo: 'Pick a target and beat the multiplier', GameType.coinflip: 'Call heads or tails', GameType.rps: 'Beat the house at rock paper scissors', GameType.darts: 'Throw a dart and hit a multiplier', GameType.scratch: 'Scratch and match three to win', GameType.diamonds: 'Match gems for big wins', GameType.war: 'Draw a higher card than the dealer', GameType.tower: 'Climb the tower, pick the safe tile', GameType.chicken: 'Cross the road, cash out before you are hit', GameType.pump: 'Pump the balloon, cash out before it pops', GameType.moles: 'Pick a hole and avoid the mole'}[t] ?? '';
    }
  }

  static String howTo(GameType t) {
    switch (t) {
      case GameType.slots:
        return 'Set your bet and spin. Three matching symbols on the payline pay your bet times the multiplier. Every result is decided on the server before the reels stop.';
      case GameType.roulette:
        return 'Place chips on numbers, colours or dozens, then spin. Numbers pay 35 to 1, dozens 2 to 1, and colours, odd or even and high or low pay 1 to 1. Zero loses every outside bet.';
      case GameType.blackjack:
        return 'Get closer to 21 than the dealer without going over. Hit to take a card, Stand to hold, or Double to double your bet for one more card. The dealer stands on every 17.';
      case GameType.dice:
        return 'Pick a target and choose roll under or over. The lower your chance of winning, the higher the multiplier. The roll is a number from 0.00 to 99.99.';
      case GameType.plinko:
        return 'Choose your risk and the number of rows, then drop the ball. It bounces left or right at every peg and lands in a slot that pays its multiplier. Slots at the edges pay the most.';
      case GameType.crash:
        return 'The multiplier climbs from 1.00x. Cash out any time to win your bet times the multiplier, but if it crashes first the bet is lost.';
      case GameType.mines:
        return 'Choose how many mines hide on the 5 by 5 board, then open tiles. Every safe tile raises your multiplier. Cash out before you hit a mine, or lose the bet.';
      case GameType.baccarat:
        return 'Bet on the Player or the Banker hand, whichever you think will finish closer to 9, or on a Tie. Cards are drawn automatically by the standard rules.';
      case GameType.wheel:
        return 'Choose a risk level and spin. The wheel has 20 segments and the one it stops on pays its multiplier. Low risk pays often, high risk pays big and rarely.';
      case GameType.keno:
        return 'Pick 1 to 10 numbers from 1 to 40, then 10 numbers are drawn. The more of your picks are drawn, the more you win. Fewer picks pay less but hit more often.';
      case GameType.hilo:
        return 'A card is shown. Guess whether the next card is higher or lower (the same rank counts for both). Every right guess raises your multiplier. Cash out any time, or a wrong guess loses the bet.';
      default:
        return const {GameType.limbo: 'Choose a target multiplier. A multiplier is drawn: if it reaches your target you win your bet times the target. A higher target pays more but is less likely.', GameType.coinflip: 'Call heads or tails and flip. Call it right and your bet pays almost double.', GameType.rps: 'Pick rock, paper or scissors. Beat the house to win about double. A draw returns your bet.', GameType.darts: 'Choose a risk level and throw. The segment you hit pays its multiplier. Low risk pays often, high risk pays big and rarely.', GameType.scratch: 'Scratch the card. Match three tiles to win the prize. Prizes go from small to very large.', GameType.diamonds: 'Five gems are drawn from seven colours. Matching gems pay: two pairs, three, a full house, four or five of a kind.', GameType.war: 'You and the dealer each draw one card. The higher card wins. A tie returns your bet.', GameType.tower: 'Pick one tile on every level. Safe tiles move you up and raise your multiplier. A bad tile ends the round. Cash out any time.', GameType.chicken: 'Press CROSS to move to the next lane. Each lane raises your multiplier, but a lane can be unsafe. Cash out any time.', GameType.pump: 'Press PUMP to inflate the balloon. Every pump raises your multiplier but the balloon can pop. Cash out before it does.', GameType.moles: 'Pick one hole on every level. A safe hole raises your multiplier, a mole ends the round. Cash out any time.'}[t] ?? '';
    }
  }

  static String _top(GameType t) {
    switch (t) {
      case GameType.slots:
        return '×100';
      case GameType.roulette:
        return '×36';
      case GameType.blackjack:
        return '×2.5';
      case GameType.dice:
        return '×48.5';
      case GameType.crash:
        return '×5,000';
      case GameType.plinko:
        return '×400';
      case GameType.mines:
        return '×1,000+';
      case GameType.baccarat:
        return '×9';
      case GameType.wheel:
        return '×10';
      case GameType.keno:
        return '×1,000+';
      case GameType.hilo:
        return '×1,000+';
      default:
        return const {GameType.limbo: '×1,000', GameType.coinflip: '×2', GameType.rps: '×2', GameType.darts: '×16', GameType.scratch: '×100', GameType.diamonds: '×50', GameType.war: '×2', GameType.tower: '×1,000+', GameType.chicken: '×1,000+', GameType.pump: '×25', GameType.moles: '×1,000+'}[t] ?? '';
    }
  }

  @override
  Widget build(BuildContext context) => ContentWidth(maxWidth: 720, child: _page(context));

  Widget _page(BuildContext context) {
    final favs = context.select((ProfileCubit c) => c.state.settings.favourites);
    final settings = context.select((ProfileCubit c) => c.state.settings);
    final uid = context.select((ProfileCubit c) => c.state.dataId);
    final isFav = favs.contains(game.id);
    final accent = GameArtStyle.accentOf(game.kind);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 280,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GameArt(kind: game.kind, borderRadius: 0),
              ],
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      IconSquareButton(icon: Icons.chevron_left_rounded, iconSize: 26, semanticLabel: 'Back', onPressed: () => Navigator.of(context).maybePop()),
                      const Spacer(),
                      IconSquareButton(
                        icon: isFav ? Icons.star_rounded : Icons.star_border_rounded,
                        iconColor: isFav ? AppColors.gold : null,
                        semanticLabel: isFav ? 'Remove from favourites' : 'Add to favourites',
                        onPressed: () {
                          final next = isFav ? [for (final f in favs) if (f != game.id) f] : [...favs, game.id];
                          context.read<ProfileCubit>().updateSettings(settings.copyWith(favourites: next));
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 120, 20, 24),
                    children: [
                      const ServerBanner(),
                      Text(game.name, style: AppText.heading(30, letterSpacing: -1)),
                      const SizedBox(height: 4),
                      Text(_blurb(game.type), style: AppText.body(14, color: AppColors.textMuted)),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(child: _Stat(label: 'Min bet', value: formatCredits(game.minBet, decimals: 0))),
                          const SizedBox(width: 10),
                          Expanded(child: _Stat(label: 'Max bet', value: formatCredits(game.maxBet, decimals: 0))),
                          const SizedBox(width: 10),
                          Expanded(child: _Stat(label: 'Top prize', value: _top(game.type), color: accent)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text('HOW IT WORKS', style: AppText.label()),
                      const SizedBox(height: 8),
                      Text(howTo(game.type), style: AppText.body(14, color: AppColors.textMuted, height: 1.55)),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            PillButton(label: 'How to play', icon: Icons.help_outline_rounded, onPressed: () => openGuide(context, game.type)),
                            PillButton(label: 'Help & FAQ', icon: Icons.support_agent_rounded, onPressed: () => pushPage<void>(context, HelpPage(category: faqCategoryFor(game.type)))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text('YOUR LAST RESULTS', style: AppText.label()),
                      const SizedBox(height: 10),
                      if (uid.isNotEmpty) _Last(uid: uid, game: game.type),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).padding.bottom),
                  child: Row(
                    children: [
                      IconSquareButton(icon: Icons.verified_user_outlined, iconColor: AppColors.green, size: 64, iconSize: 26, semanticLabel: 'Provably fair', onPressed: () => openFairness(context)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppButton(
                          label: context.watch<CatalogCubit>().state.locked ? (context.watch<CatalogCubit>().state.paused ? 'MAINTENANCE' : 'UNAVAILABLE') : 'PLAY NOW',
                          variant: AppButtonVariant.success,
                          height: 64,
                          onPressed: context.watch<CatalogCubit>().state.locked ? null : () {
                            final nav = Navigator.of(context);
                            nav.pushReplacement(MaterialPageRoute<void>(builder: (_) => gamePage(game)));
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => StatTile(label: label, value: value, valueColor: (color ?? AppColors.text));
}

class _Last extends StatelessWidget {
  const _Last({required this.uid, required this.game});
  final String uid;
  final GameType game;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GameRound>>(
      stream: context.read<UserRepository>().watchRounds(uid, game: game, limit: 30),
      builder: (context, snap) {
        final rounds = (snap.data ?? const <GameRound>[]).take(8).toList();
        if (rounds.isEmpty) {
          return Text(snap.hasData ? 'No rounds yet. Your results show up here.' : 'Loading…', style: AppText.body(13, color: AppColors.textDim));
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final r in rounds) MultiplierPill(value: r.returned, decimals: r.returned == r.returned.roundToDouble() ? 0 : 2)],
        );
      },
    );
  }
}
