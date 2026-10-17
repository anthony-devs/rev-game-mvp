import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../core/api/api_client.dart';
import '../core/api/rounds_hub.dart';
import 'rounds_sheet.dart';

/// Small pill with the rounds the player has left. Tap to see when free rounds come back or buy more.
///
/// ```dart
/// const RoundsPill()
/// ```
class RoundsPill extends StatefulWidget {
  const RoundsPill({super.key, this.compact = false});

  /// Smaller, for crowded bars.
  final bool compact;

  @override
  State<RoundsPill> createState() => _RoundsPillState();
}

class _RoundsPillState extends State<RoundsPill> {
  @override
  void initState() {
    super.initState();
    PlayMode.live.addListener(_load);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    PlayMode.live.removeListener(_load);
    super.dispose();
  }

  void _load() {
    if (!mounted) return;
    if (RoundsHub.of(PlayMode.isLive).value == null) refreshRounds(context.read<ApiClient>());
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: PlayMode.live,
        builder: (context, live, _) => ValueListenableBuilder<RoundsInfo?>(
          valueListenable: RoundsHub.of(live),
          builder: (context, info, _) {
            if (info != null && !info.enabled) return const SizedBox.shrink();
            final n = info?.available;
            final color = n == null ? AppColors.textMuted : (n == 0 ? AppColors.loss : (n <= 3 ? AppColors.gold : AppColors.text));
            return PressScale(
              onTap: () => showRoundsSheet(context),
              child: Container(
                height: widget.compact ? 36 : 40,
                padding: EdgeInsets.symmetric(horizontal: widget.compact ? 7 : 11),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(color: n == 0 ? AppColors.loss : AppColors.lineStrong, width: 1.2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, size: widget.compact ? 16 : 18, color: color),
                    SizedBox(width: widget.compact ? 2 : 4),
                    Text(n == null ? '–' : '$n', style: AppText.body(widget.compact ? 13 : 14, weight: FontWeight.w700, color: color)),
                  ],
                ),
              ),
            );
          },
        ),
      );
}
