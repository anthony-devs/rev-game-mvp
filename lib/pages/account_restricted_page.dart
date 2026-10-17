import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../auth/bloc/auth_bloc.dart';
import '../components/components.dart';
import '../games/game_support.dart';
import '../model/model.dart';
import '../support/attachments.dart';
import '../support/new_ticket_page.dart';
import '../support/support_api.dart';
import '../support/support_models.dart';
import '../user/bloc/profile_cubit.dart';
import '../support/faq_data.dart';
import 'help_page.dart';

/// "May 3, 14:05"
String formatWhen(DateTime t) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final l = t.toLocal();
  final hh = l.hour.toString().padLeft(2, '0');
  final mm = l.minute.toString().padLeft(2, '0');
  return '${l.day} ${m[l.month - 1]} ${l.year}, $hh:$mm';
}

/// "2d 4h", "3h 12m", "8m", "under a minute"
String formatLeft(Duration d) {
  if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
  if (d.inMinutes >= 1) return '${d.inMinutes}m';
  return 'under a minute';
}

class _Look {
  const _Look(this.icon, this.color, this.title, this.lead, this.next);
  final IconData icon;
  final Color color;
  final String title;
  final String lead;
  final String next;
}

_Look _lookFor(StandingType t) {
  switch (t) {
    case StandingType.ban:
      return _Look(Icons.block_rounded, AppColors.loss, 'Account banned', 'This account can no longer play.', 'You can appeal this decision below. Explain what happened and what has changed. If the appeal is approved, you will get access back.');
    case StandingType.suspension:
      return const _Look(Icons.pause_circle_outline_rounded, Color(0xFFFF9A5A), 'Account suspended', 'Play is paused for now.', 'Your access comes back by itself when the suspension ends. If you think this is a mistake, you can appeal below.');
    case StandingType.investigation:
      return _Look(Icons.manage_search_rounded, AppColors.blue, 'Account under review', 'We are looking into recent activity.', 'Nothing is needed from you unless we asked for something below. Play comes back as soon as the review is finished.');
    case StandingType.payoutRestriction:
      return _Look(Icons.money_off_csred_rounded, AppColors.gold, 'Account restricted', 'Play and credit rewards are on hold.', 'Follow the steps below, then appeal so we can lift the restriction.');
  }
}

/// Shown instead of the app while the account is banned, suspended, under
/// review or restricted. Updates live: when staff lift the action, the app
/// opens again by itself.
class AccountRestrictedPage extends StatefulWidget {
  const AccountRestrictedPage({super.key});

  @override
  State<AccountRestrictedPage> createState() => _AccountRestrictedPageState();
}

class _AccountRestrictedPageState extends State<AccountRestrictedPage> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _openAppeal(StandingAction a) async {
    await showAppBottomSheet<void>(
      context,
      title: 'Appeal this decision',
      child: _AppealForm(action: a),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<ProfileCubit>();
    final now = DateTime.now();
    final active = cubit.state.standing.activeAt(now);
    final top = cubit.state.blockingAction ?? (active.isEmpty ? null : active.first);
    if (top == null) return const AppScaffold(body: SizedBox.shrink());

    final look = _lookFor(top.type);
    final others = [for (final a in active) if (a.id != top.id) a];

    return AppScaffold(
      glowColor: look.color,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 36, 20, 28),
        children: [
          Center(
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(shape: BoxShape.circle, color: look.color.withValues(alpha: .14), border: Border.all(color: look.color.withValues(alpha: .55), width: 2)),
              child: Icon(look.icon, size: 50, color: look.color),
            ),
          ),
          const SizedBox(height: 22),
          Text(look.title, textAlign: TextAlign.center, style: AppText.heading(28, letterSpacing: -.8)),
          const SizedBox(height: 6),
          Text(look.lead, textAlign: TextAlign.center, style: AppText.body(15, color: AppColors.textMuted)),
          if (top.expiresAt != null) ...[
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: look.color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20), border: Border.all(color: look.color.withValues(alpha: .4))),
                child: Text('Ends in ${formatLeft(top.expiresAt!.difference(now))}  ·  ${formatWhen(top.expiresAt!)}', style: AppText.body(12.5, weight: FontWeight.w700, color: look.color)),
              ),
            ),
          ],
          const SizedBox(height: 22),
          _InfoCard(label: 'REASON', child: Text(top.reason.isEmpty ? 'No reason was recorded.' : top.reason, style: AppText.body(14.5, height: 1.5))),
          const SizedBox(height: 12),
          _InfoCard(
            label: 'WHAT HAPPENS NEXT',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (top.publicNote.isNotEmpty) ...[
                  Text(top.publicNote, style: AppText.body(14.5, height: 1.5)),
                  const SizedBox(height: 10),
                ],
                Text(look.next, style: AppText.body(13.5, color: AppColors.textMuted, height: 1.5)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _appeal(top, now),
          if (others.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('ALSO ON YOUR ACCOUNT', style: AppText.label()),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final a in others) _Chip(label: _lookFor(a.type).title)]),
          ],
          const SizedBox(height: 26),
          AppButton(
            label: 'Message support about this',
            icon: Icons.chat_bubble_outline_rounded,
            variant: AppButtonVariant.outline,
            height: 52,
            fontSize: 15,
            onPressed: () => pushPage<void>(context, NewTicketPage(category: TicketCategory.restriction, subject: 'About my account: ${look.title.toLowerCase()}')),
          ),
          const SizedBox(height: 10),
          AppButton(label: 'Help Centre', variant: AppButtonVariant.ghost, height: 48, fontSize: 14, onPressed: () => pushPage<void>(context, const HelpPage(category: FaqCategory.support))),
          const SizedBox(height: 10),
          AppButton(
            label: 'Sign out',
            variant: AppButtonVariant.ghost,
            height: 48,
            fontSize: 14,
            onPressed: () => context.read<AuthBloc>().add(const AuthSignOutRequested()),
          ),
        ],
      ),
    );
  }

  Widget _appeal(StandingAction a, DateTime now) {
    if (!a.appealAllowed) {
      return _InfoCard(label: 'APPEAL', child: Text('This decision cannot be appealed. Contact support if you need help.', style: TextStyle(color: AppColors.textMuted, height: 1.5)));
    }
    if (a.appealStatus == AppealStatus.pending) {
      return _InfoCard(
        label: 'APPEAL',
        accent: AppColors.gold,
        child: Row(
          children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.gold)),
            const SizedBox(width: 12),
            Expanded(child: Text('Your appeal is being reviewed. This screen updates by itself when we decide.', style: AppText.body(13.5, height: 1.5))),
          ],
        ),
      );
    }
    final retry = a.appealRetryAt;
    final waiting = a.appealStatus == AppealStatus.rejected && retry != null && retry.isAfter(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (a.appealStatus == AppealStatus.rejected)
          _InfoCard(
            label: 'APPEAL REJECTED',
            accent: AppColors.loss,
            child: Text((a.appealResponse ?? '').isEmpty ? 'Your appeal was not approved.' : a.appealResponse!, style: AppText.body(14, height: 1.5)),
          ),
        if (a.appealStatus == AppealStatus.rejected) const SizedBox(height: 10),
        AppButton(
          label: waiting ? 'Appeal again in ${formatLeft(retry.difference(now))}' : (a.appealStatus == AppealStatus.rejected ? 'Appeal again' : 'Appeal this decision'),
          variant: AppButtonVariant.gold,
          height: 56,
          fontSize: 15,
          onPressed: waiting ? null : () => _openAppeal(a),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.label, required this.child, this.accent});
  final String label;
  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent?.withValues(alpha: .5) ?? AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.label(color: accent ?? AppColors.textDim)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.line)),
        child: Text(label, style: AppText.body(12, weight: FontWeight.w600, color: AppColors.textSoft)),
      );
}

class _AppealForm extends StatefulWidget {
  const _AppealForm({required this.action});
  final StandingAction action;

  @override
  State<_AppealForm> createState() => _AppealFormState();
}

class _AppealFormState extends State<_AppealForm> {
  final _text = TextEditingController();
  late final AttachmentsController _files = AttachmentsController(context.read<SupportApi>());
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    _files.dispose();
    super.dispose();
  }

  bool get _valid => _text.text.trim().length >= 20 && !_files.busy;

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await context.read<ProfileCubit>().appeal(widget.action.id, _text.text.trim(), attachments: _files.ids);
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(context, 'Appeal sent. We will review it.');
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = ProfileCubit.errorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tell us what happened and what you have done to fix it. Be honest and specific, at least 20 characters.', style: AppText.body(13.5, color: AppColors.textMuted, height: 1.5)),
          const SizedBox(height: 14),
          AppTextField(
            label: 'Your appeal',
            controller: _text,
            maxLines: 5,
            hint: 'e.g. I shared my phone with my brother. It will not happen again.',
            onChanged: (_) => setState(() {}),
            errorText: _error,
          ),
          const SizedBox(height: 6),
          Text('${_text.text.trim().length}/1000', style: AppText.body(11, color: AppColors.textFaint)),
          const SizedBox(height: 14),
          Text('EVIDENCE (OPTIONAL)', style: AppText.label()),
          const SizedBox(height: 4),
          Text('Screenshots, a video or a PDF can make a difference.', style: AppText.body(12.5, color: AppColors.textDim)),
          const SizedBox(height: 10),
          ListenableBuilder(listenable: _files, builder: (_, __) => AttachmentStrip(controller: _files)),
          const SizedBox(height: 16),
          ListenableBuilder(
            listenable: _files,
            builder: (_, __) => AppButton(
              label: _files.busy ? 'Uploading files…' : 'Send appeal',
              variant: AppButtonVariant.success,
              height: 56,
              loading: _sending,
              onPressed: _valid && !_sending ? _send : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// A slim notice on the home screen for things that don't stop play:
/// paused free credits, probation, a payout restriction that leaves play open.
class StandingBanner extends StatelessWidget {
  const StandingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.select((ProfileCubit c) => c.state);
    final soft = s.softActions;
    String? text;
    Color color = AppColors.gold;
    if (soft.isNotEmpty) {
      final a = soft.first;
      text = '${_lookFor(a.type).title}: free credits are paused${a.expiresAt != null ? ' until ${formatWhen(a.expiresAt!)}' : ''}.';
    } else if (s.onProbation) {
      color = AppColors.purple;
      text = 'Probation until ${formatWhen(s.standing.probationUntil!)}: bets up to ${formatCredits(s.standing.probationMaxBet, decimals: 0)}, free credits paused.';
    }
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: .4))),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: AppText.body(12, color: AppColors.textSoft, height: 1.4))),
          ],
        ),
      ),
    );
  }
}
