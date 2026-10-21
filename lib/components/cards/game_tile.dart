import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/app_text.dart';
import '../core/press_scale.dart';
import 'game_art.dart';

/// Square game card with art and name/tag overlay.
///
/// ```dart
/// GameTile(title: 'Roulette', tag: 'Table', kind: GameKind.roulette, onTap: openRoulette)
/// GameTile(title: 'Poker', tag: 'Coming soon', kind: GameKind.soon, onTap: null)
/// GameTile(title: 'Custom', image: AssetImage('assets/x.png'), onTap: open)
/// ```
class GameTile extends StatelessWidget {
  const GameTile({
    super.key,
    required this.title,
    required this.onTap,
    this.tag,
    this.kind = GameKind.slots,
    this.image,
    this.aspectRatio = 1,
    this.badge,
  });

  final String title;
  final String? tag;
  final GameKind kind;

  /// Optional artwork that replaces the painted [GameArt].
  final ImageProvider? image;
  final double aspectRatio;

  /// Optional corner widget, e.g. `DemoBadge(label: 'NEW')`.
  final Widget? badge;

  /// `null` renders the tile as disabled (coming soon).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null) Image(image: image!, fit: BoxFit.cover) else GameArt(kind: kind, borderRadius: 0),
              if (image != null)
                const ColoredBox(color: Color(0x73000000)), // flat scrim so the title stays readable
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black.withValues(alpha: .6),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(16, weight: FontWeight.w700, color: Colors.white)),
                      if (tag != null) Text(tag!, style: AppText.body(12, color: const Color(0xFFC9C9D2))),
                    ],
                  ),
                ),
              ),
              if (badge != null) Positioned(top: 10, right: 10, child: badge!),
            ],
          ),
        ),
      ),
    );
  }
}
