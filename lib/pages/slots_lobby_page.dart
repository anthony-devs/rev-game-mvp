import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../catalog/catalog_cubit.dart';
import '../components/components.dart';
import '../games/game_launcher.dart';
import '../model/model.dart';
import '../user/bloc/profile_cubit.dart';
import 'widgets/lobby_tile.dart';

/// L3. The Slots tab: the playable slot, then the ones on their way.
class SlotsLobbyPage extends StatefulWidget {
  const SlotsLobbyPage({super.key});

  @override
  State<SlotsLobbyPage> createState() => _SlotsLobbyPageState();
}

class _SlotsLobbyPageState extends State<SlotsLobbyPage> {
  int _chip = 0;
  static const _labels = ['All', 'Classic', '3 reel', 'Favourites'];

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogCubit>().state;
    final favs = context.select((ProfileCubit c) => c.state.settings.favourites);
    final slots = [for (final g in catalog.playable) if (g.type == GameType.slots) g];
    final soon = [for (final g in catalog.upcoming) if (g.type == GameType.slots) g];
    // Golden Reels is both a classic and a 3 reel slot.
    final shown = [for (final g in slots) if (_chip == 3 ? favs.contains(g.id) : true) g];

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 4, AppSpacing.screen, 120),
      children: [
        Text('Slots', style: AppText.heading(28, letterSpacing: -1)),
        const SizedBox(height: 14),
        SizedBox(height: 38, child: FilterChipRow(labels: _labels, selectedIndex: _chip, onSelected: (i) => setState(() => _chip = i), padding: EdgeInsets.zero)),
        const SizedBox(height: 16),
        if (shown.isEmpty)
          const StatusView(icon: Icons.star_border_rounded, title: 'No favourites yet', message: 'Open a game and tap the star to save it here.')
        else
          for (final g in shown) ...[
            _Featured(game: g),
            const SizedBox(height: 14),
          ],
        if (soon.isNotEmpty && _chip != 3) ...[
          const SizedBox(height: 8),
          const SectionHeader(title: 'Coming soon', icon: Icons.lock_outline_rounded, iconColor: Colors.white, padding: EdgeInsets.zero),
          const SizedBox(height: 12),
          TileGrid(children: [for (final g in soon) LobbyTile(game: g, onTap: () => openGame(context, g))]),
        ],
      ],
    );
  }
}

class _Featured extends StatelessWidget {
  const _Featured({required this.game});
  final GameInfo game;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: () => openGame(context, game, viaDetails: true),
      child: SizedBox(
        height: 190,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const GameArt(kind: GameKind.slots, borderRadius: 0),
              const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xCC000000)]))),
              Positioned(
                left: 18,
                right: 18,
                bottom: 16,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(game.name, style: AppText.body(20, weight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text('3 reels · 1 payline · RTP ${(game.rtp * 100).round()}%', style: AppText.body(12, color: Colors.white70)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
                      child: Text('Play', style: AppText.body(14, weight: FontWeight.w800, color: AppColors.bg)),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 14,
                left: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(10)),
                  child: Text('NEW', style: AppText.body(10, weight: FontWeight.w800, color: AppColors.bg, letterSpacing: 1, height: 1)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
