import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../auth/bloc/auth_bloc.dart';
import '../components/components.dart';
import '../core/api/api_client.dart';
import '../games/game_support.dart';
import '../user/data/user_repository.dart';
import 'attachment_view.dart';
import 'attachments.dart';
import 'new_ticket_page.dart';
import 'support_api.dart';
import 'support_cubit.dart';
import 'support_models.dart';
import 'tickets_page.dart';

/// One conversation with support. Replies appear live.
class TicketChatPage extends StatefulWidget {
  const TicketChatPage({super.key, required this.ticketId});

  final String ticketId;

  @override
  State<TicketChatPage> createState() => _TicketChatPageState();
}

class _TicketChatPageState extends State<TicketChatPage> {
  late final SupportApi _api = context.read<SupportApi>();
  late final String _uid = context.read<AuthBloc>().state.user.id;
  late final Stream<List<TicketMessage>> _stream = context.read<UserRepository>().watchTicketMessages(_uid, widget.ticketId);
  late final AttachmentsController _files = AttachmentsController(_api);
  final _text = TextEditingController();
  bool _sending = false;
  DateTime _lastMark = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _text.dispose();
    _files.dispose();
    super.dispose();
  }

  /// Opening the conversation clears the red dot (throttled while Firestore catches up).
  void _markRead(Ticket? t) {
    if (t == null || !t.unread) return;
    final now = DateTime.now();
    if (now.difference(_lastMark).inSeconds < 4) return;
    _lastMark = now;
    _api.markRead(t.id).catchError((Object _) {});
  }

  bool get _canSend => !_sending && !_files.busy && (_text.text.trim().isNotEmpty || _files.ids.isNotEmpty);

  Future<void> _send() async {
    final text = _text.text.trim();
    setState(() => _sending = true);
    try {
      await _api.reply(widget.ticketId, text, _files.ids);
      _text.clear();
      _files.clear();
    } catch (e) {
      if (mounted) showToast(context, e is ApiException ? e.message : 'Could not send. Please try again.', error: true);
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _confirmClose() async {
    await showAppBottomSheet<void>(
      context,
      title: 'Close this conversation?',
      child: Column(
        children: [
          Text('You will not be able to reply any more. You can always start a new one.', style: AppText.body(14, color: AppColors.textMuted, height: 1.5)),
          const SizedBox(height: 18),
          AppButton(
            label: 'Close conversation',
            variant: AppButtonVariant.danger,
            height: 52,
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await _api.close(widget.ticketId);
              } catch (e) {
                if (mounted) showToast(context, e is ApiException ? e.message : 'Could not close it.', error: true);
              }
            },
          ),
          const SizedBox(height: 10),
          AppButton(label: 'Keep it open', variant: AppButtonVariant.outline, height: 50, onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ticket = context.select((SupportCubit c) => c.state.byId(widget.ticketId));
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead(ticket));
    final closed = ticket?.isClosed ?? false;

    return AppScaffold(
      glowColor: AppColors.blue,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                IconSquareButton(icon: Icons.chevron_left_rounded, iconSize: 26, semanticLabel: 'Back', onPressed: () => Navigator.of(context).maybePop()),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ticket?.subject ?? 'Conversation', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(16, weight: FontWeight.w700)),
                      if (ticket != null) Text(ticket.status.label, style: AppText.body(12, weight: FontWeight.w600, color: statusColor(ticket.status))),
                    ],
                  ),
                ),
                if (ticket != null && !closed) IconSquareButton(icon: Icons.more_horiz_rounded, semanticLabel: 'More', onPressed: _confirmClose),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<TicketMessage>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) return StatusView.offline(onRetry: () => setState(() {}));
                if (!snap.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
                final msgs = snap.data!.reversed.toList();
                if (msgs.isEmpty) return const StatusView(icon: Icons.forum_outlined, title: 'No messages yet');
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) => _Bubble(message: msgs[i]),
                );
              },
            ),
          ),
          if (ticket?.status == TicketStatus.solved)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Marked as solved. Reply here if you still need help and it will reopen.', textAlign: TextAlign.center, style: AppText.body(12, color: AppColors.gold)),
            ),
          if (closed) _closedBar() else _composer(),
        ],
      ),
    );
  }

  Widget _closedBar() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.line))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('This conversation is closed.', style: AppText.body(13, color: AppColors.textMuted)),
          const SizedBox(height: 10),
          AppButton(label: 'Start a new one', variant: AppButtonVariant.outline, height: 48, fontSize: 14, onPressed: () => pushPage<void>(context, const NewTicketPage())),
        ],
      ),
    );
  }

  Widget _composer() {
    return ListenableBuilder(
      listenable: _files,
      builder: (context, _) => Container(
        padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + MediaQuery.of(context).padding.bottom + MediaQuery.of(context).viewInsets.bottom),
        decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.line))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(alignment: Alignment.centerLeft, child: AttachmentStrip(controller: _files, showAdd: false)),
            if (_files.files.isNotEmpty) const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconSquareButton(icon: Icons.attach_file_rounded, semanticLabel: 'Attach a file', onPressed: _files.slotsLeft > 0 ? () => showAttachSheet(context, _files) : null),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _text,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 2000,
                    onChanged: (_) => setState(() {}),
                    textCapitalization: TextCapitalization.sentences,
                    style: AppText.body(15),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'Write a message…',
                      hintStyle: AppText.body(15, color: AppColors.textFaint),
                      filled: true,
                      fillColor: AppColors.surfaceAlt,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconSquareButton(
                  icon: Icons.arrow_upward_rounded,
                  semanticLabel: 'Send',
                  iconColor: _canSend ? AppColors.bg : AppColors.textFaint,
                  onPressed: _canSend ? _send : null,
                  filled: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final TicketMessage message;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final mine = !m.fromAgent;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .8),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          decoration: BoxDecoration(
            color: mine ? AppColors.purpleDeep : AppColors.surfaceAlt,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 4),
              bottomRight: Radius.circular(mine ? 4 : 18),
            ),
            border: mine ? null : Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.support_agent_rounded, size: 14, color: AppColors.gold),
                      const SizedBox(width: 4),
                      Text(m.author.isEmpty ? 'Support' : '${m.author} · Support', style: AppText.body(11.5, weight: FontWeight.w700, color: AppColors.gold)),
                    ],
                  ),
                ),
              if (m.text.isNotEmpty) Text(m.text, style: AppText.body(15, height: 1.4)),
              if (m.attachments.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [for (final a in m.attachments) AttachmentView(attachment: a)]),
              ],
              const SizedBox(height: 4),
              Align(alignment: Alignment.centerRight, child: Text(ticketTime(m.createdAt), style: AppText.body(10.5, color: Colors.white54))),
            ],
          ),
        ),
      ),
    );
  }
}
