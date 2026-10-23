import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../auth/bloc/auth_bloc.dart';
import '../auth/require_sign_in.dart';
import '../bets/bets_feed.dart';
import '../catalog/catalog_cubit.dart';
import '../catalog/server_banner.dart';
import '../components/components.dart';
import '../games/game_launcher.dart';
import '../games/game_support.dart' show pushPage;
import '../model/model.dart';
import '../shell/shell_cubit.dart';
import '../user/bloc/profile_cubit.dart';
import 'widgets/level_streak_card.dart';
import 'widgets/play_first.dart';
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
  bool _searching = false;

  /// Chips: All, one per group (the server decides the order), Favourites.
  int _chipIndex(ShellState s, List<GameGroupInfo> groups) {
    if (s.favouritesOnly) return groups.length + 1;
    if (s.filter == null) return 0;
    final i = groups.indexWhere((g) => g.id == s.filter);
    return i < 0 ? 0 : i + 1;
  }

  static IconData _groupIcon(String id) => switch (id) {
        'originals' => Icons.diamond_outlined,
        'crash' => Icons.rocket_launch_rounded,
        'adventure' => Icons.terrain_rounded,
        'table' => Icons.style_rounded,
        'slots' => Icons.casino_rounded,
        'quick' => Icons.bolt_rounded,
        _ => Icons.grid_view_rounded,
      };

  void _chip(BuildContext context, int i, List<GameGroupInfo> groups) {
    final shell = context.read<ShellCubit>();
    if (i == 0) {
      shell.setFilter(null);
    } else if (i <= groups.length) {
      shell.setFilter(groups[i - 1].id);
    } else {
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
    final signedIn = context.select((AuthBloc b) => b.state.isAuthenticated);
    final q = _query.trim().toLowerCase();
    final groups = catalog.groups;

    bool keep(GameInfo g) {
      if (q.isNotEmpty && !g.name.toLowerCase().contains(q) && !g.tag.toLowerCase().contains(q)) return false;
      if (shell.favouritesOnly) return favs.contains(g.id);
      if (shell.filter != null && g.group != shell.filter) return false;
      return true;
    }

    final playable = [for (final g in catalog.playable) if (keep(g)) g];
    final upcoming = [for (final g in catalog.upcoming) if (keep(g)) g];
    final browsing = q.isEmpty && shell.filter == null && !shell.favouritesOnly;

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
          if (!requireSignIn(context)) return;
          AppHaptics.selection();
          final next = isFav ? [for (final f in favs) if (f != g.id) f] : [...favs, g.id];
          context.read<ProfileCubit>().updateSettings(settings.copyWith(favourites: next));
        },
        // Slots opens its details first, like the design; the rest start playing.
        onTap: () => openGame(context, g, viaDetails: g.type == GameType.slots),
      );
    }

    // Popular: at most three, picked by the server.
    final byId = {for (final g in catalog.playable) g.id: g};
    var popular = [for (final id in catalog.popular) if (byId[id] != null) byId[id]!];
    if (popular.isEmpty) popular = catalog.playable.take(3).toList();
    popular = [for (final g in popular) if (!const {'slots', 'wheel', 'plinko'}.contains(g.id)) g].take(3).toList();
    final heroSlots = byId['slots'], heroWheel = byId['wheel'], heroPlinko = byId['plinko'];
    final showHero = heroSlots != null || heroWheel != null || heroPlinko != null;

    // Tall cover cards in a sideways row, one row per section.
    Widget row(List<GameInfo> games) => SizedBox(
          height: 176,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: games.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => SizedBox(width: 130, child: tile(games[i])),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 4, AppSpacing.screen, 120),
      children: [
        // Search is one small button; it opens a slim field in place of the filter chips.
        SizedBox(
          height: 52,
          child: Row(children: [
            PressScale(
              onTap: () => setState(() {
                _searching = !_searching;
                if (!_searching) _query = '';
              }),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
                child: Icon(_searching ? Icons.close_rounded : Icons.search_rounded, size: 20, color: AppColors.textSoft),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _searching
                  ? SearchField(hint: 'Search games', height: 52, autofocus: true, onChanged: (v) => setState(() => _query = v))
                  : CategoryTileRow(
                      labels: ['All', for (final g in groups) g.name, 'Favourites'],
                      icons: [Icons.apps_rounded, for (final g in groups) _groupIcon(g.id), Icons.star_rounded],
                      selectedIndex: _chipIndex(shell, groups),
                      onSelected: (i) => _chip(context, i, groups),
                    ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        const ServerBanner(padding: EdgeInsets.only(bottom: 14)),
        if (signedIn && !live) ...[const LevelStreakCard(), const SizedBox(height: 12)],
        if (playable.isEmpty && upcoming.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: StatusView(
              icon: shell.favouritesOnly ? Icons.star_border_rounded : Icons.search_off_rounded,
              title: shell.favouritesOnly ? 'No favourites yet' : 'No games found',
              message: shell.favouritesOnly ? (signedIn ? 'Tap the star on a game to save it here.' : 'Sign in to save your favourite games.') : 'Try another word or clear the filter.',
            ),
          ),
        if (browsing) ...[
          if (showHero) ...[
            SectionHeader(title: 'Play these first', icon: Icons.bolt_rounded, iconColor: AppColors.gold, padding: EdgeInsets.zero),
            const SizedBox(height: 12),
            PlayFirst(
              slots: heroSlots,
              wheel: heroWheel,
              plinko: heroPlinko,
              onOpen: (g) => openGame(context, g, viaDetails: g.type == GameType.slots),
            ),
            const SizedBox(height: 24),
          ],
          if (popular.isNotEmpty) ...[
            SectionHeader(title: 'Popular', icon: Icons.local_fire_department_outlined, iconColor: AppColors.text, padding: EdgeInsets.zero),
            const SizedBox(height: 12),
            row(popular),
            const SizedBox(height: 24),
          ],
          for (final grp in groups) ...[
            Builder(builder: (context) {
              final games = [for (final g in playable) if (g.group == grp.id) g];
              if (games.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SectionHeader(
                    title: grp.name,
                    actionLabel: games.length > 3 ? 'See all' : null,
                    onAction: games.length > 3 ? () => context.read<ShellCubit>().setFilter(grp.id) : null,
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 12),
                  row(games),
                ]),
              );
            }),
          ],
          const BetsFeed(),
          const SizedBox(height: 16),
        ] else if (playable.isNotEmpty) ...[
          TileGrid(children: [for (final g in playable) tile(g)]),
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
