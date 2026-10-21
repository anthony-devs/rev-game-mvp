import 'package:flutter/material.dart';

import '../components/components.dart';
import '../model/model.dart';


/// Name, short code, icon and artwork of the arcade games.
class _Arc {
  const _Arc(this.title, this.abbr, this.icon, this.kind);
  final String title;
  final String abbr;
  final IconData icon;
  final GameKind kind;
}

const _arcade = <GameType, _Arc>{
  GameType.limbo: _Arc('Limbo', 'LI', Icons.rocket_launch_rounded, GameKind.limbo),
  GameType.coinflip: _Arc('Coin Flip', 'CF', Icons.monetization_on_outlined, GameKind.coinflip),
  GameType.rps: _Arc('Rock Paper Scissors', 'RP', Icons.back_hand_outlined, GameKind.rps),
  GameType.darts: _Arc('Darts', 'DA', Icons.gps_fixed_rounded, GameKind.darts),
  GameType.scratch: _Arc('Scratch Card', 'SC', Icons.confirmation_number_outlined, GameKind.scratch),
  GameType.diamonds: _Arc('Diamonds', 'DM', Icons.diamond_outlined, GameKind.diamonds),
  GameType.war: _Arc('Card War', 'CW', Icons.style_rounded, GameKind.war),
  GameType.tower: _Arc('Tower', 'TW', Icons.stairs_rounded, GameKind.tower),
  GameType.chicken: _Arc('Chicken Road', 'CH', Icons.directions_walk_rounded, GameKind.chicken),
  GameType.pump: _Arc('Pump', 'PU', Icons.bubble_chart_rounded, GameKind.pump),
  GameType.moles: _Arc('Moles', 'MO', Icons.grass_rounded, GameKind.moles),
};

/// Which arcade game a type is, or null for the older games.
bool isArcade(GameType t) => _arcade.containsKey(t);

/// Names, icons and text for rounds, shared by Wallet, History and Fairness.
extension GameTypeX on GameType {
  String get title {
    switch (this) {
      case GameType.slots:
        return 'Slots';
      case GameType.roulette:
        return 'Euro Roulette';
      case GameType.blackjack:
        return 'Blackjack';
      case GameType.dice:
        return 'Dice';
      case GameType.crash:
        return 'Dash Crash';
      case GameType.plinko:
        return 'Plinko';
      case GameType.mines:
        return 'Mines';
      case GameType.baccarat:
        return 'Baccarat';
      case GameType.wheel:
        return 'Lucky Wheel';
      case GameType.keno:
        return 'Keno';
      case GameType.hilo:
        return 'Hi-Lo';
      default:
        return _arcade[this]!.title;
    }
  }

  String get abbr {
    switch (this) {
      case GameType.slots:
        return 'SL';
      case GameType.roulette:
        return 'RO';
      case GameType.blackjack:
        return 'BJ';
      case GameType.dice:
        return 'DI';
      case GameType.crash:
        return 'CR';
      case GameType.plinko:
        return 'PL';
      case GameType.mines:
        return 'MI';
      case GameType.baccarat:
        return 'BA';
      case GameType.wheel:
        return 'WH';
      case GameType.keno:
        return 'KE';
      case GameType.hilo:
        return 'HL';
      default:
        return _arcade[this]!.abbr;
    }
  }

  IconData get icon {
    switch (this) {
      case GameType.slots:
        return Icons.casino_outlined;
      case GameType.roulette:
        return Icons.album_outlined;
      case GameType.blackjack:
        return Icons.style_outlined;
      case GameType.dice:
        return Icons.casino_rounded;
      case GameType.crash:
        return Icons.show_chart_rounded;
      case GameType.plinko:
        return Icons.scatter_plot_rounded;
      case GameType.mines:
        return Icons.grid_view_rounded;
      case GameType.baccarat:
        return Icons.style_rounded;
      case GameType.wheel:
        return Icons.data_usage_rounded;
      case GameType.keno:
        return Icons.apps_rounded;
      case GameType.hilo:
        return Icons.swap_vert_rounded;
      default:
        return _arcade[this]!.icon;
    }
  }

  GameKind get kind {
    switch (this) {
      case GameType.slots:
        return GameKind.slots;
      case GameType.roulette:
        return GameKind.roulette;
      case GameType.blackjack:
        return GameKind.blackjack;
      case GameType.dice:
        return GameKind.dice;
      case GameType.crash:
        return GameKind.crash;
      case GameType.plinko:
        return GameKind.plinko;
      case GameType.mines:
        return GameKind.mines;
      case GameType.baccarat:
        return GameKind.baccarat;
      case GameType.wheel:
        return GameKind.wheel;
      case GameType.keno:
        return GameKind.keno;
      case GameType.hilo:
        return GameKind.hilo;
      default:
        return _arcade[this]!.kind;
    }
  }
}

/// The artwork for a catalog entry: the slot themes have their own, everything else follows its type.
extension GameInfoArt on GameInfo {
  GameKind get kind {
    switch (id) {
      case 'lucky7':
        return GameKind.lucky7;
    }
    return type.kind;
  }
}

extension GameRoundX on GameRound {
  /// "Cashed out at 3.42x", "17 black", "No win" ...
  String get summary {
    if (label.isNotEmpty) return label;
    switch (status) {
      case RoundStatus.won:
        return 'Won';
      case RoundStatus.cashedOut:
        return 'Cashed out';
      case RoundStatus.push:
        return 'Push';
      case RoundStatus.lost:
        return 'No win';
      default:
        return 'In progress';
    }
  }

  /// What came back per credit bet. 0 when the round paid nothing.
  double get returned => payout > 0 ? multiplier : 0;

  Color get tone => net > 0 ? AppColors.green : (net < 0 ? AppColors.loss : AppColors.textMuted);
}

String timeAgo(DateTime t, [DateTime? now]) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inSeconds < 45) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays == 1) return 'Yesterday';
  if (d.inDays < 7) return '${d.inDays}d ago';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${t.day} ${m[t.month - 1]}';
}

/// Rank name for a level, shown under "LEVEL n".
String levelTitle(int level) {
  if (level < 3) return 'Fresh Player';
  if (level < 10) return 'Rookie Roller';
  if (level < 20) return 'High Roller';
  if (level < 35) return 'Veteran';
  return 'Legend';
}
