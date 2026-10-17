import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../games/game_support.dart';
import '../pages/help_page.dart';
import 'support_cubit.dart';

/// Opens the Help Centre. A red dot shows when support has replied.
/// Put it anywhere: `const SupportButton()`.
class SupportButton extends StatelessWidget {
  const SupportButton({super.key, this.size = 44, this.filled = true});

  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final unread = context.select((SupportCubit c) => c.state.unread);
    return IconSquareButton(
      icon: Icons.support_agent_rounded,
      semanticLabel: unread > 0 ? 'Help and support, new reply' : 'Help and support',
      size: size,
      filled: filled,
      onPressed: () => pushPage<void>(context, const HelpPage()),
      badge: unread > 0
          ? Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: AppColors.loss, shape: BoxShape.circle, border: Border.all(color: AppColors.bg, width: 2)),
            )
          : null,
    );
  }
}

/// For the trailing side of a list row: the count of unread replies, or the usual chevron.
class SupportBadge extends StatelessWidget {
  const SupportBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final unread = context.select((SupportCubit c) => c.state.unread);
    final chevron = Icon(Icons.chevron_right_rounded, size: 22, color: AppColors.textFaint);
    if (unread == 0) return chevron;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: AppColors.loss, borderRadius: BorderRadius.circular(20)),
          child: Text('$unread new', style: AppText.body(11, weight: FontWeight.w700, color: Colors.white)),
        ),
        const SizedBox(width: 4),
        chevron,
      ],
    );
  }
}
