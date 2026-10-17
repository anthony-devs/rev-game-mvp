import 'package:flutter/material.dart';

import '../../components/components.dart';
import '../../model/model.dart';
import '../round_format.dart';

/// The 3-across game tile from the design (112 x 152). Locked when coming soon.
class LobbyTile extends StatelessWidget {
  const LobbyTile({super.key, required this.game, required this.onTap, this.favourite = false, this.onFavourite, this.offline = false});

  final GameInfo game;
  final VoidCallback onTap;
  final bool favourite;
  final VoidCallback? onFavourite;

  /// The game server can't be reached: show the tile as unavailable.
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final soon = game.comingSoon;
    final paused = (!game.enabled || offline) && !soon;
    final kind = soon ? GameKind.soon : game.type.kind;
    return PressScale(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 112 / 152,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              GameArt(kind: kind, borderRadius: 0),
              if (soon || paused) Container(color: AppColors.bg.withValues(alpha: .45), alignment: Alignment.center, child: Icon(soon ? Icons.lock_outline_rounded : (offline ? Icons.cloud_off_rounded : Icons.pause_circle_outline_rounded), size: 30, color: AppColors.textMuted)),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(game.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(12, weight: FontWeight.w700, height: 1.2)),
                      const SizedBox(height: 2),
                      Text(soon ? 'Coming soon' : (paused ? (offline ? 'Server offline' : 'Paused') : game.tag), style: AppText.body(10, color: AppColors.textMuted, height: 1.2)),
                    ],
                  ),
                ),
              ),
              if (onFavourite != null && !soon)
                Positioned(
                  top: 4,
                  right: 4,
                  child: PressScale(
                    onTap: onFavourite,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(favourite ? Icons.star_rounded : Icons.star_border_rounded, size: 20, color: favourite ? AppColors.gold : AppColors.textMuted),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three tiles per row, as in the design.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 3) {
      final row = <Widget>[];
      for (var j = 0; j < 3; j++) {
        if (j > 0) row.add(const SizedBox(width: 12));
        row.add(Expanded(child: i + j < children.length ? children[i + j] : const SizedBox.shrink()));
      }
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 12));
      rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: row));
    }
    return Column(children: rows);
  }
}
