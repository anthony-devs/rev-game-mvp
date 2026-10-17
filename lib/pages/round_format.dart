import 'package:flutter/material.dart';

import '../components/components.dart';
import '../model/model.dart';

/// Names, icons and text for rounds, shared by Wallet, History and Fairness.
extension GameTypeX on GameType {
  String get title {
    switch (this) {
      case GameType.slots:
        return 'Golden Reels';
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
    }
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
