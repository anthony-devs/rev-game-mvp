import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import 'catalog_cubit.dart';

/// Warning shown while the game server can't be reached or isn't set up.
/// Shows nothing when the server is fine.
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
    if (!state.offline) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: AppColors.loss.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.loss.withValues(alpha: .4)),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, size: 22, color: AppColors.loss),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Game server unavailable', style: AppText.body(14, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    '${state.message ?? "Can't reach the game server."} Games are paused until it is back. Retrying automatically.',
                    style: AppText.body(12, color: AppColors.textMuted, height: 1.4),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => context.read<CatalogCubit>().refresh(),
              child: Text('Retry', style: AppText.body(13, weight: FontWeight.w700, color: AppColors.loss)),
            ),
          ],
        ),
      ),
    );
  }
}
