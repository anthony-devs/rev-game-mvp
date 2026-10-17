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
    }
  }

  static String _how(GameType t) {
    switch (t) {
      case GameType.slots:
        return 'Set your bet and spin. Three matching symbols on the payline pay your bet times the multiplier. Every result is decided on the server before the reels stop.';
      case GameType.roulette:
        return 'Place chips on numbers, colours or dozens, then spin. Numbers pay 35 to 1, dozens 2 to 1, and colours, odd or even and high or low pay 1 to 1. Zero loses every outside bet.';
      case GameType.blackjack:
        return 'Get closer to 21 than the dealer without going over. Hit to take a card, Stand to hold, or Double to double your bet for one more card. The dealer stands on every 17.';
      case GameType.dice:
        return 'Pick a target and choose roll under or over. The lower your chance of winning, the higher the multiplier. The roll is a number from 0.00 to 99.99.';
      case GameType.crash:
        return 'The multiplier climbs from 1.00x. Cash out any time to win your bet times the multiplier, but if it crashes first the bet is lost.';
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final favs = context.select((ProfileCubit c) => c.state.settings.favourites);
    final settings = context.select((ProfileCubit c) => c.state.settings);
    final uid = context.select((ProfileCubit c) => c.state.dataId);
    final isFav = favs.contains(game.id);
    final accent = GameArtStyle.accentOf(game.type.kind);

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
                GameArt(kind: game.type.kind, borderRadius: 0),
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
                      Text(_how(game.type), style: AppText.body(14, color: AppColors.textMuted, height: 1.55)),
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
                          label: context.watch<CatalogCubit>().state.offline ? 'SERVER OFFLINE' : 'PLAY NOW',
                          variant: AppButtonVariant.success,
                          height: 64,
                          onPressed: context.watch<CatalogCubit>().state.offline ? null : () {
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
