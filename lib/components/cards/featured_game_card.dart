import 'package:flutter/material.dart';

import '../buttons/app_button.dart';
import '../core/app_colors.dart';
import '../core/app_text.dart';
import 'game_art.dart';

/// Large hero card for the lobby with a Play button.
///
/// ```dart
/// FeaturedGameCard(title: 'Golden Reels', subtitle: 'Classic 3-reel slots', kind: GameKind.slots, onPlay: openSlots)
/// ```
class FeaturedGameCard extends StatelessWidget {
  const FeaturedGameCard({
    super.key,
    required this.title,
    required this.onPlay,
    this.subtitle,
    this.kind = GameKind.slots,
    this.image,
    this.height = 190,
    this.playLabel = 'Play now',
    this.eyebrow = 'FEATURED',
  });

  final String title;
  final String? subtitle;
  final GameKind kind;
  final ImageProvider? image;
  final double height;
  final String playLabel;
  final String? eyebrow;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image != null) Image(image: image!, fit: BoxFit.cover) else GameArt(kind: kind, borderRadius: 0),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Color(0xE6000000), Colors.transparent]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (eyebrow != null) Text(eyebrow!, style: AppText.label(color: AppColors.gold)),
                  const SizedBox(height: 4),
                  Text(title, style: AppText.heading(26)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: AppText.body(13, color: AppColors.textMuted)),
                  ],
                  const SizedBox(height: 14),
                  AppButton(label: playLabel, onPressed: onPlay, variant: AppButtonVariant.success, height: 44, expanded: false, fontSize: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
