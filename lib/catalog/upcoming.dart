import 'package:flutter/material.dart';

import '../components/components.dart';
import '../model/model.dart';

/// What the app shows about a game that isn't out yet: its artwork, a short pitch and what to
/// expect. Keyed by the game's slug (its catalog id without the `soon-` prefix), so when the
/// game launches under the same slug the waitlist follows it.
class UpcomingInfo {
  const UpcomingInfo({required this.kind, required this.tagline, required this.about, required this.features, required this.icon});

  final GameKind kind;
  final String tagline;
  final String about;
  final List<String> features;
  final IconData icon;

  Color get accent => GameArtStyle.accentOf(kind);
}

const Map<String, UpcomingInfo> _info = {
  'mines': UpcomingInfo(
    kind: GameKind.mines,
    icon: Icons.grid_view_rounded,
    tagline: 'Find the gems, dodge the mines',
    about: 'Uncover tiles on a grid. Every gem raises your multiplier, every mine ends the round. Cash out whenever you like.',
    features: ['Pick your number of mines', 'Cash out any time', 'Provably fair'],
  ),
  'baccarat': UpcomingInfo(
    kind: GameKind.baccarat,
    icon: Icons.style_outlined,
    tagline: 'Player, Banker or Tie',
    about: 'The classic table game. Bet on the Player, the Banker or a Tie and watch the cards dealt from a full shoe.',
    features: ['Player, Banker and Tie bets', 'Standard drawing rules', 'Provably fair'],
  ),
  'lucky7': UpcomingInfo(
    kind: GameKind.lucky7,
    icon: Icons.looks_one_rounded,
    tagline: 'Chase the triple sevens',
    about: 'A fast, classic slot built around sevens, bars and bells with a bold paytable.',
    features: ['3 reels, 1 payline', 'Classic symbols', 'Provably fair'],
  ),
};

String slugOf(String gameId) => gameId.startsWith('soon-') ? gameId.substring(5) : gameId;

/// Details for a coming-soon game. Unknown ids still get a sensible generic page.
UpcomingInfo upcomingInfoFor(GameInfo game) {
  final slug = slugOf(game.id);
  final key = _info.containsKey(slug) ? slug : _info.keys.firstWhere((k) => slug.contains(k), orElse: () => '');
  return _info[key] ??
      const UpcomingInfo(
        kind: GameKind.soon,
        icon: Icons.auto_awesome_rounded,
        tagline: 'On its way',
        about: 'We are working on this game. Join the waitlist and we will point it out in your lobby as soon as it is live.',
        features: ['Provably fair'],
      );
}
