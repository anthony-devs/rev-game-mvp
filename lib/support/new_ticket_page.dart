import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../core/api/api_cache.dart';
import '../core/api/api_client.dart';
import 'attachments.dart';
import 'support_api.dart';
import 'support_models.dart';
import 'ticket_chat_page.dart';

/// Start a conversation with support. Pass [category], [subject] or [message]
/// to open it already filled in (e.g. from a round or a restriction).
class NewTicketPage extends StatefulWidget {
  const NewTicketPage({super.key, this.category, this.subject = '', this.message = ''});

  final TicketCategory? category;
  final String subject;
  final String message;

  @override
  State<NewTicketPage> createState() => _NewTicketPageState();
}

class _NewTicketPageState extends State<NewTicketPage> {
  late final TextEditingController _subject = TextEditingController(text: widget.subject);
  late final TextEditingController _message = TextEditingController(text: widget.message);
  late final AttachmentsController _files = AttachmentsController(context.read<SupportApi>());
  late TicketCategory? _category = widget.category;
  bool _sending = false;
  String? _error;

  static const _draftKey = 'draft.ticket';

  @override
  void initState() {
    super.initState();
    // Coming back after a back-press or a crash: put back what was typed (unless a screen opened this one pre-filled).
    if (widget.subject.isEmpty && widget.message.isEmpty) _restoreDraft();
  }

  Future<void> _restoreDraft() async {
    final d = await ApiCache.read(_draftKey);
    if (d == null || !mounted) return;
    if (_subject.text.isNotEmpty || _message.text.isNotEmpty) return; // the player already started again
    setState(() {
      _subject.text = (d['subject'] ?? '').toString();
      _message.text = (d['message'] ?? '').toString();
      final c = (d['category'] ?? '').toString();
      for (final v in TicketCategory.values) {
        if (v.name == c && _category == null) _category = v;
      }
    });
  }

  void _saveDraft() {
    if (_subject.text.trim().isEmpty && _message.text.trim().isEmpty) {
      ApiCache.remove(_draftKey);
    } else {
      ApiCache.write(_draftKey, {'subject': _subject.text, 'message': _message.text, 'category': _category?.name ?? ''});
    }
  }

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    _files.dispose();
    super.dispose();
  }

  bool get _valid =>
      _category != null && _subject.text.trim().length >= 3 && (_message.text.trim().length >= 5 || _files.ids.isNotEmpty);

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final id = await context.read<SupportApi>().createTicket(
            category: _category!,
            subject: _subject.text.trim(),
            message: _message.text.trim(),
            attachments: _files.ids,
          );
      ApiCache.remove(_draftKey);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => TicketChatPage(ticketId: id)));
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e is ApiException ? e.message : 'Could not send. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      glowColor: AppColors.blue,
      body: ListenableBuilder(
        listenable: _files,
        builder: (context, _) => ListView(
          padding: EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, 28 + MediaQuery.of(context).viewInsets.bottom),
          children: [
            SubPageBar(title: 'Message support', onBack: () => Navigator.of(context).maybePop(), padding: const EdgeInsets.symmetric(vertical: 8)),
            const SizedBox(height: 8),
            Text('WHAT IS THIS ABOUT?', style: AppText.label()),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in TicketCategory.values) PillChip(label: c.label, icon: c.icon, selected: _category == c, onTap: () {
                  setState(() => _category = c);
                  _saveDraft();
                }),
              ],
            ),
            const SizedBox(height: 18),
            AppTextField(label: 'Title', controller: _subject, hint: 'e.g. My balance dropped after a round', onChanged: (_) {
              setState(() {});
              _saveDraft();
            }, textInputAction: TextInputAction.next),
            const SizedBox(height: 14),
            AppTextField(label: 'Tell us what happened', controller: _message, maxLines: 6, hint: 'Which game, roughly when, and what you expected.', onChanged: (_) {
              setState(() {});
              _saveDraft();
            }),
            const SizedBox(height: 6),
            Text('${_message.text.trim().length}/2000', style: AppText.body(11, color: AppColors.textFaint)),
            const SizedBox(height: 14),
            AttachmentStrip(controller: _files),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: AppText.body(13, color: AppColors.loss)),
            ],
            const SizedBox(height: 20),
            AppButton(
              label: _files.busy ? 'Uploading files…' : 'Send',
              variant: AppButtonVariant.success,
              height: 56,
              loading: _sending,
              onPressed: _valid && !_sending && !_files.busy ? _send : null,
            ),
            const SizedBox(height: 10),
            Text('We usually reply within one working day. You can follow the conversation from Help.', textAlign: TextAlign.center, style: AppText.body(12, color: AppColors.textDim, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
