import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blackjack_game/blackjack_page.dart';
import '../catalog/catalog_cubit.dart';
import '../crash_game/crash_page.dart';
import '../dice_game/dice_page.dart';
import '../catalog/upcoming.dart';
import '../pages/coming_soon_page.dart';
import '../user/bloc/profile_cubit.dart';
import '../plinko_game/plinko_page.dart';
import '../model/model.dart';
import '../pages/game_detail_page.dart';
import '../pages/system_pages.dart';
import '../roulette_game/roulette_page.dart';
import '../session/session_guard.dart';
import '../catalog/server_banner.dart';
import '../slots_game/slots_page.dart';
import 'game_support.dart';

/// Opens a game from a lobby tile, with every check the design asks for:
/// coming soon, paused (maintenance), a break or limit in force.
void openGame(BuildContext context, GameInfo game, {bool viaDetails = false}) {
  if (game.comingSoon) {
    pushPage<void>(context, ComingSoonPage(game: game));
    return;
  }
  if (!game.enabled) {
    pushPage<void>(context, GameUnavailablePage(name: game.name));
    return;
  }
  final catalog = context.read<CatalogCubit>();
  if (catalog.state.locked) {
    unawaited(catalog.refresh());
    pushPage<void>(
      context,
      GameUnavailablePage(
        name: game.name,
        title: catalog.state.noticeTitle,
        icon: catalog.state.noticeIcon,
        message: catalog.state.noticeBody,
      ),
    );
    return;
  }
  final reason = context.read<SessionGuard>().blockReason();
  if (reason != null) {
    pushPage<void>(context, BreakPage(reason: reason));
    return;
  }
  // A game the player was waiting for: opening it clears the NEW mark.
  final profile = context.read<ProfileCubit>();
  final slug = slugOf(game.id);
  if (profile.state.settings.waitlist.contains(slug)) {
    unawaited(profile.updateSettings(profile.state.settings.copyWith(waitlist: [for (final w in profile.state.settings.waitlist) if (w != slug) w])));
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
    case GameType.plinko:
      return PlinkoPage(info: game);
  }
}

/// Looks the catalog entry up fresh, so a game switched off remotely is honoured.
GameInfo? catalogGame(BuildContext context, GameType type) => context.read<CatalogCubit>().state.byType(type);
