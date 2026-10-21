import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../core/api/api_client.dart';
import '../session/session_guard.dart';
import 'limits_page.dart';

/// X1. Shown when the game server or the network cannot be reached.
class OfflinePage extends StatelessWidget {
  const OfflinePage({super.key, this.onRetry, this.message});

  final VoidCallback? onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      glowColor: AppColors.textDim,
      body: Column(
        children: [
          SubPageBar(title: '', onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: StatusView(
              icon: Icons.wifi_off_rounded,
              title: "You're offline",
              message: message ?? 'Check your internet connection and try again. Your balance is safe.',
              actionLabel: onRetry == null ? null : 'Try again',
              onAction: onRetry,
            ),
          ),
        ],
      ),
    );
  }
}

/// X1 inline. Use inside a page body instead of a whole screen.
class OfflineView extends StatelessWidget {
  const OfflineView({super.key, required this.onRetry, this.message, this.error});

  final VoidCallback onRetry;
  final String? message;

  /// The failure being shown. A failure that is not "phone has no internet" reads as downtime.
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final e = error is ApiException ? error as ApiException : null;
    final slow = e != null && e.isSlow;
    final unreachable = e != null && e.code == 'unreachable';
    final down = e != null && !e.isOffline && !slow && !unreachable;
    return StatusView(
      icon: slow ? Icons.network_check_rounded : (down || unreachable ? Icons.cloud_off_rounded : Icons.wifi_off_rounded),
      title: slow ? 'Slow connection' : (unreachable ? "Can't reach our servers" : (down ? "We're experiencing downtime" : "You're offline")),
      message: message ??
          (slow
              ? 'Your connection is too slow to load this. Move to a stronger signal and try again. Your balance is safe.'
              : unreachable
                  ? "We couldn't connect to the game service. This is usually a connection problem on your side. Your balance is safe."
                  : down
                      ? "Our service is temporarily unavailable. We're working to restore it. Your balance is safe."
                      : 'Check your internet connection and try again. Your balance is safe.'),
      actionLabel: 'Try again',
      onAction: onRetry,
    );
  }
}

/// X2. A game that is paused or not out yet.
class GameUnavailablePage extends StatelessWidget {
  const GameUnavailablePage({
    super.key,
    this.name,
    this.comingSoon = false,
    this.message,
    this.icon,
    this.title,
  });

  final String? name;
  final bool comingSoon;
  final String? message;
  final IconData? icon;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final heading = title ?? (comingSoon ? 'Coming soon' : 'Game unavailable');
    final text = message ??
        (comingSoon
            ? '${name ?? 'This game'} is on its way. We will add it in a future update.'
            : 'This game is paused right now. ${PlayMode.isLive ? 'Your money' : 'Your coins'} is safe, and any round in progress is settled.');
    return AppScaffold(
      glowColor: comingSoon ? AppColors.purple : AppColors.gold,
      body: Column(
        children: [
          SubPageBar(title: name ?? '', onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 112,
                      height: 150,
                      child: GameTile(title: name ?? 'More soon', tag: comingSoon ? 'Coming' : 'Paused', kind: GameKind.soon, aspectRatio: 112 / 150, onTap: null),
                    ),
                    const SizedBox(height: 28),
                    Text(heading, style: AppText.body(22, weight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(text, textAlign: TextAlign.center, style: AppText.body(14, color: AppColors.textDim, height: 1.5)),
                    const SizedBox(height: 28),
                    AppButton(label: 'Back to lobby', onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst)),
                    const SizedBox(height: 10),
                    AppButton(
                      label: 'View game history',
                      variant: AppButtonVariant.outline,
                      height: 52,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of a game while a break or a limit is active.
class BreakPage extends StatelessWidget {
  const BreakPage({super.key, required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      glowColor: AppColors.blue,
      body: Column(
        children: [
          SubPageBar(title: '', onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: StatusView(
              icon: Icons.self_improvement_rounded,
              title: 'Taking a break',
              message: reason,
              color: AppColors.blue,
              actionLabel: 'Play limits',
              onAction: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const LimitsPage())),
            ),
          ),
        ],
      ),
    );
  }
}

/// X3. Placeholder layout while the lobby loads.
class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget row() => const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Expanded(child: SkeletonBox(height: 152, radius: 16)),
            SizedBox(width: 12),
            Expanded(child: SkeletonBox(height: 152, radius: 16)),
            SizedBox(width: 12),
            Expanded(child: SkeletonBox(height: 152, radius: 16)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(height: 52, radius: 16),
          const SizedBox(height: 16),
          const SkeletonBox(height: 76, radius: 18),
          const SizedBox(height: 20),
          const SkeletonBox(width: 140, height: 20),
          const SizedBox(height: 12),
          row(),
          row(),
        ],
      ),
    );
  }
}

/// X4. The reality check dialog. Returns when the player chose.
Future<void> showRealityCheck(BuildContext context) async {
  final guard = context.read<SessionGuard>();
  final s = guard.state;
  final minutes = s.playedFor(DateTime.now()).inMinutes;
  final net = s.net;
  final choice = await showAppDialog<String>(
    context,
    AppDialogCard(
      icon: Icons.schedule_rounded,
      iconColor: AppColors.blue,
      title: 'You have played for ${minutes < 1 ? 'a while' : '$minutes minutes'}',
      message: 'A quick check on your session.',
      body: Column(
        children: [
          Row(
            children: [
              Expanded(child: _Stat(label: 'Total bet', value: formatCredits(s.totalBet, decimals: 0))),
              const SizedBox(width: 10),
              Expanded(
                child: _Stat(
                  label: 'Net result',
                  value: formatSigned(net),
                  color: net > 0 ? AppColors.green : (net < 0 ? AppColors.loss : AppColors.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AppButton(label: 'Leave the game', variant: AppButtonVariant.ghost, height: 44, fontSize: 14, onPressed: () => Navigator.of(context).pop('leave')),
        ],
      ),
      primaryLabel: 'Continue playing',
      onPrimary: () => Navigator.of(context).pop('continue'),
      secondaryLabel: 'Take a break',
      onSecondary: () => Navigator.of(context).pop('break'),
    ),
  );
  if (!context.mounted) return;
  if (choice == 'break') {
    guard.acknowledge();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LimitsPage()));
  } else if (choice == 'leave') {
    guard.acknowledge();
    Navigator.of(context).popUntil((r) => r.isFirst);
  } else {
    guard.acknowledge();
  }
}

/// Shown when the session loss limit is reached.
Future<void> showLossLimitReached(BuildContext context) async {
  final guard = context.read<SessionGuard>();
  final choice = await showAppDialog<String>(
    context,
    AppDialogCard(
      icon: Icons.shield_outlined,
      iconColor: AppColors.loss,
      title: 'Loss limit reached',
      message: 'You have lost your session limit of ${PlayMode.amount(guard.state.net.abs(), decimals: 0)}${PlayMode.isLive ? '' : ' coins'}. Play is paused. This is the limit you set.',
      primaryLabel: 'Leave the game',
      onPrimary: () => Navigator.of(context).pop('leave'),
      secondaryLabel: 'Change my limits',
      onSecondary: () => Navigator.of(context).pop('limits'),
    ),
  );
  if (!context.mounted) return;
  if (choice == 'limits') {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LimitsPage()));
  } else {
    Navigator.of(context).popUntil((r) => r.isFirst);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Column(
        children: [
          Text(label.toUpperCase(), style: AppText.label(size: 10)),
          const SizedBox(height: 4),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: AppText.number(16, color: (color ?? AppColors.text)))),
        ],
      ),
    );
  }
}
