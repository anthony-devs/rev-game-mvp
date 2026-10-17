import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../catalog/catalog_cubit.dart';
import '../catalog/server_banner.dart';
import '../components/components.dart';
import '../games/game_launcher.dart';
import '../model/model.dart';
import '../shell/shell_cubit.dart';
import '../user/bloc/profile_cubit.dart';
import 'widgets/level_streak_card.dart';
import 'widgets/next_up_banner.dart';
import '../catalog/upcoming.dart';
import 'widgets/lobby_tile.dart';

/// L1. The Casino tab: search, chips, level and streak, popular and new games.
class LobbyPage extends StatefulWidget {
  const LobbyPage({super.key});

  @override
  State<LobbyPage> createState() => _LobbyPageState();
}

class _LobbyPageState extends State<LobbyPage> {
  String _query = '';

  static const _chipLabels = ['All', 'Slots', 'Table', 'Instant', 'Favourites'];

  int _chipIndex(ShellState s) {
    if (s.favouritesOnly) return 4;
    switch (s.filter) {
      case null:
        return 0;
      case GameGroup.slots:
        return 1;
      case GameGroup.table:
        return 2;
      case GameGroup.instant:
        return 3;
    }
  }

  void _chip(BuildContext context, int i) {
    final shell = context.read<ShellCubit>();
    switch (i) {
      case 0:
        shell.setFilter(null);
      case 1:
        shell.setFilter(GameGroup.slots);
      case 2:
        shell.setFilter(GameGroup.table);
      case 3:
        shell.setFilter(GameGroup.instant);
      default:
        shell.setFilter(null, favouritesOnly: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogCubit>().state;
    final shell = context.watch<ShellCubit>().state;
    final favs = context.select((ProfileCubit c) => c.state.settings.favourites);
    final settings = context.select((ProfileCubit c) => c.state.settings);
    final live = context.select((ProfileCubit c) => c.state.live);
    final q = _query.trim().toLowerCase();

    bool keep(GameInfo g) {
      if (q.isNotEmpty && !g.name.toLowerCase().contains(q) && !g.tag.toLowerCase().contains(q)) return false;
      if (shell.favouritesOnly) return favs.contains(g.id);
      if (shell.filter != null && g.group != shell.filter) return false;
      return true;
    }

    final popular = [for (final g in catalog.playable) if (keep(g)) g];
    final upcoming = [for (final g in catalog.upcoming) if (keep(g)) g];

    Widget tile(GameInfo g) {
      final isFav = favs.contains(g.id);
      return LobbyTile(
        game: g,
        offline: catalog.locked,
        maintenance: catalog.paused,
        isNew: !g.comingSoon && settings.waitlist.contains(slugOf(g.id)),
        joined: g.comingSoon && settings.waitlist.contains(slugOf(g.id)),
        favourite: isFav,
        onFavourite: () {
          AppHaptics.selection();
          final next = isFav ? [for (final f in favs) if (f != g.id) f] : [...favs, g.id];
          context.read<ProfileCubit>().updateSettings(settings.copyWith(favourites: next));
        },
        // Slots opens its details first, like the design; the rest start playing.
        onTap: () => openGame(context, g, viaDetails: g.type == GameType.slots),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 4, AppSpacing.screen, 120),
      children: [
        SearchField(hint: 'Search games', onChanged: (v) => setState(() => _query = v)),
        const SizedBox(height: 14),
        SizedBox(
          height: 38,
          child: FilterChipRow(labels: _chipLabels, selectedIndex: _chipIndex(shell), onSelected: (i) => _chip(context, i), padding: EdgeInsets.zero),
        ),
        const SizedBox(height: 16),
        const ServerBanner(padding: EdgeInsets.only(bottom: 14)),
        if (!live) ...[const LevelStreakCard(), const SizedBox(height: 20)],
        if (popular.isEmpty && upcoming.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: StatusView(
              icon: shell.favouritesOnly ? Icons.star_border_rounded : Icons.search_off_rounded,
              title: shell.favouritesOnly ? 'No favourites yet' : 'No games found',
              message: shell.favouritesOnly ? 'Tap the star on a game to save it here.' : 'Try another word or clear the filter.',
            ),
          ),
        if (popular.isNotEmpty) ...[
          SectionHeader(title: 'Popular Games', icon: Icons.local_fire_department_outlined, iconColor: AppColors.text, padding: EdgeInsets.zero),
          const SizedBox(height: 12),
          TileGrid(children: [for (final g in popular) tile(g)]),
          const SizedBox(height: 22),
        ],
        if (upcoming.isNotEmpty) ...[
          SectionHeader(title: 'Coming soon', icon: Icons.diamond_outlined, iconColor: AppColors.text, padding: EdgeInsets.zero),
          const SizedBox(height: 12),
          NextUpBanner(
            game: upcoming.first,
            joined: settings.waitlist.contains(slugOf(upcoming.first.id)),
            onTap: () => openGame(context, upcoming.first),
          ),
          const SizedBox(height: 12),
          TileGrid(children: [for (final g in upcoming) tile(g)]),
        ],
      ],
    );
  }
}
