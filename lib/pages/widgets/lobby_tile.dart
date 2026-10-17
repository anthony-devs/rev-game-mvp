import 'package:flutter/material.dart';

import '../../catalog/upcoming.dart';
import '../../components/components.dart';
import '../../model/model.dart';
import '../round_format.dart';

/// The 3-across game tile from the design (112 x 152). Locked when coming soon.
class LobbyTile extends StatelessWidget {
  const LobbyTile({super.key, required this.game, required this.onTap, this.favourite = false, this.onFavourite, this.offline = false, this.maintenance = false, this.isNew = false, this.joined = false});

  final GameInfo game;
  final VoidCallback onTap;
  final bool favourite;
  final VoidCallback? onFavourite;

  /// The game server can't be reached: show the tile as unavailable.
  final bool offline;
  final bool maintenance;

  /// A game the player was waiting for has launched.
  final bool isNew;

  /// The player is on this coming-soon game's waitlist.
  final bool joined;

  @override
  Widget build(BuildContext context) {
    final soon = game.comingSoon;
    final paused = (!game.enabled || offline) && !soon;
    final kind = soon ? upcomingInfoFor(game).kind : game.type.kind;
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
              if (soon || paused) Container(color: AppColors.bg.withValues(alpha: .45), alignment: Alignment.center, child: Icon(soon ? upcomingInfoFor(game).icon : (maintenance ? Icons.construction_rounded : offline ? Icons.cloud_off_rounded : Icons.pause_circle_outline_rounded), size: 30, color: AppColors.textMuted)),
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
                      Text(soon ? 'Coming soon' : (paused ? (maintenance ? 'Maintenance' : offline ? 'Unavailable' : 'Paused') : game.tag), style: AppText.body(10, color: AppColors.textMuted, height: 1.2)),
                    ],
                  ),
                ),
              ),
              if (isNew && !soon)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(8)),
                    child: Text('NEW', style: AppText.body(9, weight: FontWeight.w800, color: AppColors.onAccent, height: 1.1)),
                  ),
                ),
              if (soon)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.bg.withValues(alpha: .75), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.lineStrong)),
                    child: Text(joined ? 'ON LIST' : 'SOON', style: AppText.body(9, weight: FontWeight.w800, color: joined ? AppColors.green : AppColors.textSoft, height: 1.1)),
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

/// Game tiles in rows: three across on a phone, more on an iPad, Mac or browser.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final cols = tileColumns(box.maxWidth);
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += cols) {
          final row = <Widget>[];
          for (var j = 0; j < cols; j++) {
            if (j > 0) row.add(const SizedBox(width: 12));
            row.add(Expanded(child: i + j < children.length ? children[i + j] : const SizedBox.shrink()));
          }
          if (rows.isNotEmpty) rows.add(const SizedBox(height: 12));
          rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: row));
        }
        return Column(children: rows);
      },
    );
  }
}
