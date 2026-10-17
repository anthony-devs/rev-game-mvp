import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../games/game_support.dart';
import 'new_ticket_page.dart';
import 'support_cubit.dart';
import 'support_models.dart';
import 'ticket_chat_page.dart';

Color statusColor(TicketStatus s) {
  switch (s) {
    case TicketStatus.open:
      return AppColors.blue;
    case TicketStatus.pending:
      return AppColors.green;
    case TicketStatus.solved:
      return AppColors.gold;
    case TicketStatus.closed:
      return AppColors.textFaint;
  }
}

/// "just now", "5m", "3h", "2d", or a date.
String ticketTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 2) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${t.day} ${m[t.month - 1]}';
}

/// All of the player's conversations with support, live.
class TicketsPage extends StatelessWidget {
  const TicketsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      glowColor: AppColors.blue,
      body: Column(
        children: [
          SubPageBar(
            title: 'My conversations',
            onBack: () => Navigator.of(context).maybePop(),
            trailing: IconSquareButton(icon: Icons.add_rounded, semanticLabel: 'New message', onPressed: () => pushPage<void>(context, const NewTicketPage())),
          ),
          Expanded(
            child: BlocBuilder<SupportCubit, SupportState>(
              builder: (context, s) {
                if (!s.ready) return const Center(child: AppLoader());
                if (s.tickets.isEmpty) {
                  return StatusView(
                    icon: Icons.forum_outlined,
                    title: 'No conversations yet',
                    message: 'When you message support, the whole conversation lives here.',
                    actionLabel: 'Message support',
                    onAction: () => pushPage<void>(context, const NewTicketPage()),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 8, AppSpacing.screen, 28),
                  itemCount: s.tickets.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _TicketCard(ticket: s.tickets[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket});
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final t = ticket;
    final color = statusColor(t.status);
    return PressScale(
      onTap: () => pushPage<void>(context, TicketChatPage(ticketId: t.id)),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: t.unread ? AppColors.loss.withValues(alpha: .6) : AppColors.line)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
              child: Icon(t.category.icon, size: 20, color: AppColors.textMuted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(t.subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(15, weight: t.unread ? FontWeight.w800 : FontWeight.w600))),
                      const SizedBox(width: 8),
                      Text(ticketTime(t.updatedAt), style: AppText.body(11, color: AppColors.textDim)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(t.lastPreview.isEmpty ? '—' : '${t.lastFromAgent ? 'Support: ' : 'You: '}${t.lastPreview}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.body(13, color: AppColors.textMuted, height: 1.35)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(20)),
                        child: Text(t.status.label, style: AppText.body(11, weight: FontWeight.w700, color: color)),
                      ),
                      if (t.unread) ...[
                        const SizedBox(width: 8),
                        Text('New reply', style: AppText.body(11, weight: FontWeight.w700, color: AppColors.loss)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
