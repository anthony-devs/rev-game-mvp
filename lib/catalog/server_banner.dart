import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../games/game_support.dart';
import 'catalog_cubit.dart';

/// The words and look for each reason games can't be played. One place, so the lobby banner,
/// the game page and the "unavailable" screen always say the same thing.
extension ServiceNotice on CatalogState {
  String get noticeTitle {
    switch (issue) {
      case ServiceIssue.maintenance:
        return 'Under maintenance';
      case ServiceIssue.noConnection:
        return 'No internet connection';
      case ServiceIssue.slowConnection:
        return 'Slow connection';
      case ServiceIssue.unreachable:
        return "Can't reach our servers";
      case ServiceIssue.downtime:
      case ServiceIssue.none:
        return "We're experiencing downtime";
    }
  }

  String get noticeBody {
    switch (issue) {
      case ServiceIssue.maintenance:
        final note = (maintenance ?? '').trim();
        return '${note.isEmpty ? "We're making improvements." : note} Games are paused and your balance is safe. We\'ll be back shortly.';
      case ServiceIssue.noConnection:
        return 'Check your connection and try again. Your balance is safe.';
      case ServiceIssue.slowConnection:
        return 'Your connection is too slow for games to load right now. Move to a stronger signal and try again. Your balance is safe.';
      case ServiceIssue.unreachable:
        return "We couldn't connect to the game service. This is usually a connection problem on your side. We'll keep trying. Your balance is safe.";
      case ServiceIssue.downtime:
      case ServiceIssue.none:
        return "Games are temporarily unavailable. We're working to restore service. Your balance is safe.";
    }
  }

  IconData get noticeIcon {
    switch (issue) {
      case ServiceIssue.maintenance:
        return Icons.construction_rounded;
      case ServiceIssue.noConnection:
        return Icons.wifi_off_rounded;
      case ServiceIssue.slowConnection:
        return Icons.network_check_rounded;
      case ServiceIssue.unreachable:
        return Icons.cloud_off_rounded;
      case ServiceIssue.downtime:
      case ServiceIssue.none:
        return Icons.cloud_off_rounded;
    }
  }

  Color get noticeColor {
    switch (issue) {
      case ServiceIssue.maintenance:
        return AppColors.gold;
      case ServiceIssue.noConnection:
        return AppColors.textMuted;
      case ServiceIssue.slowConnection:
      case ServiceIssue.unreachable:
        return AppColors.gold;
      case ServiceIssue.downtime:
      case ServiceIssue.none:
        return AppColors.loss;
    }
  }

  /// Short label for the play button and lobby tiles.
  String get noticeShort => issue == ServiceIssue.maintenance ? 'Maintenance' : (issue == ServiceIssue.noConnection ? 'Offline' : (issue == ServiceIssue.slowConnection ? 'Slow connection' : 'Unavailable'));
}

/// Notice shown at the top of the lobby and game pages while games can't be played:
/// maintenance, downtime, or no connection. Shows nothing when everything is fine.
///
/// ```dart
/// const ServerBanner()
/// ```
class ServerBanner extends StatelessWidget {
  const ServerBanner({super.key, this.padding = const EdgeInsets.only(bottom: 14)});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CatalogCubit>().state;
    if (!state.locked) return const SizedBox.shrink();
    final color = state.noticeColor;
    return Padding(
      padding: padding,
      child: Semantics(
        liveRegion: true,
        container: true,
        label: '${state.noticeTitle}. ${state.noticeBody}',
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: .45)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: color.withValues(alpha: .07)))),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: color.withValues(alpha: .16), borderRadius: BorderRadius.circular(12)),
                          child: Icon(state.noticeIcon, size: 22, color: color),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(state.noticeTitle, style: AppText.body(16, weight: FontWeight.w800, height: 1.2)),
                              const SizedBox(height: 4),
                              Text(state.noticeBody, style: AppText.body(13, color: AppColors.textMuted, height: 1.45)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Checking automatically', style: AppText.body(12, color: AppColors.textDim))),
                        _CheckAgain(color: color),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Check again": presses in, shows a loader while it checks, then says what it found.
class _CheckAgain extends StatefulWidget {
  const _CheckAgain({required this.color});

  final Color color;

  @override
  State<_CheckAgain> createState() => _CheckAgainState();
}

class _CheckAgainState extends State<_CheckAgain> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    final cubit = context.read<CatalogCubit>();
    setState(() => _busy = true);
    AppHaptics.light();
    AppSound.play(Sfx.tap);
    try {
      await Future.wait([cubit.refresh(), Future<void>.delayed(const Duration(milliseconds: 700))]);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
    final s = cubit.state;
    if (!s.locked) {
      AppSound.play(Sfx.coin);
      showToast(context, "You're back online. Games are ready.");
    } else {
      showToast(context, '${s.noticeTitle}. We checked just now and will keep trying.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: _busy ? null : _run,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: widget.color.withValues(alpha: .14), borderRadius: BorderRadius.circular(12), border: Border.all(color: widget.color.withValues(alpha: .5))),
        child: _busy
            ? SizedBox(height: 16, child: FittedBox(child: AppLoader(size: 16, color: widget.color)))
            : Text('Check again', style: AppText.body(13, weight: FontWeight.w700, color: widget.color)),
      ),
    );
  }
}
