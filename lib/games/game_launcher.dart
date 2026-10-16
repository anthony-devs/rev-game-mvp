import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blackjack_game/blackjack_page.dart';
import '../catalog/catalog_cubit.dart';
import '../crash_game/crash_page.dart';
import '../dice_game/dice_page.dart';
import '../model/model.dart';
import '../pages/game_detail_page.dart';
import '../pages/system_pages.dart';
import '../roulette_game/roulette_page.dart';
import '../session/session_guard.dart';
import '../slots_game/slots_page.dart';
import 'game_support.dart';

/// Opens a game from a lobby tile, with every check the design asks for:
/// coming soon, paused (maintenance), a break or limit in force.
void openGame(BuildContext context, GameInfo game, {bool viaDetails = false}) {
  if (game.comingSoon) {
    pushPage<void>(context, GameUnavailablePage(name: game.name, comingSoon: true));
    return;
  }
  if (!game.enabled) {
    pushPage<void>(context, GameUnavailablePage(name: game.name));
    return;
  }
  final reason = context.read<SessionGuard>().blockReason();
  if (reason != null) {
    pushPage<void>(context, BreakPage(reason: reason));
    return;
  }
  if (viaDetails) {
    pushPage<void>(context, GameDetailPage(game: game));
    return;
  }
  pushPage<void>(context, gamePage(game));
}

/// The playable screen for a game.
Widget gamePage(GameInfo game) {
  switch (game.type) {
    case GameType.slots:
      return SlotsPage(info: game);
    case GameType.crash:
      return CrashPage(info: game);
    case GameType.roulette:
      return RoulettePage(info: game);
    case GameType.blackjack:
      return BlackjackPage(info: game);
    case GameType.dice:
      return DicePage(info: game);
  }
}

/// Looks the catalog entry up fresh, so a game switched off remotely is honoured.
GameInfo? catalogGame(BuildContext context, GameType type) => context.read<CatalogCubit>().state.byType(type);
