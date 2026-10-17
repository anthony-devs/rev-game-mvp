import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../auth/bloc/auth_bloc.dart';
import '../components/components.dart';
import '../games/game_support.dart';
import '../support/faq_data.dart';
import '../support/new_ticket_page.dart';
import '../support/support_cubit.dart';
import '../support/tickets_page.dart';
import 'fairness_page.dart';

/// Where players write to when they have no account (or no connection). Replace before release.
const String kSupportEmail = 'support@revgames.example';

/// The Help Centre: answers by topic, then a real conversation with support.
///
/// Open it on a topic from anywhere: `HelpPage(category: FaqCategory.blackjack)`.
class HelpPage extends StatefulWidget {
  const HelpPage({super.key, this.openFairness = false, this.category});

  /// Start with the "How do I verify a round?" answer open.
  final bool openFairness;

  /// Start on one section.
  final FaqCategory? category;

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  String _query = '';
  late FaqCategory? _cat = widget.openFairness ? FaqCategory.fairness : widget.category;

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final list = [
      for (final f in kFaqs)
        if ((q.isNotEmpty || _cat == null || f.category == _cat) && (q.isEmpty || f.q.toLowerCase().contains(q) || f.a.toLowerCase().contains(q))) f,
    ];
    return AppScaffold(
      glowColor: AppColors.blue,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, 32),
        children: [
          SubPageBar(title: 'Help Centre', onBack: () => Navigator.of(context).maybePop(), padding: const EdgeInsets.symmetric(vertical: 8)),
          const SizedBox(height: 8),
          SearchField(hint: 'Search help', onChanged: (v) => setState(() => _query = v)),
          const SizedBox(height: 14),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              children: [
                PillChip(label: 'All', selected: _cat == null, onTap: () => setState(() => _cat = null)),
                for (final c in FaqCategory.values) ...[
                  const SizedBox(width: 8),
                  PillChip(label: c.label, icon: c.icon, selected: _cat == c, onTap: () => setState(() => _cat = c)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (list.isEmpty)
            const InfoCard(title: 'No answers found', message: 'Try other words, or message support below.')
          else
            ListGroup(
              children: [
                for (final f in list)
                  FaqTile(
                    key: ValueKey('${f.q}$q${_cat?.name}'),
                    question: f.q,
                    answer: f.a,
                    initiallyExpanded: (widget.openFairness && f.id == 'fair-verify') || (q.isNotEmpty && list.length == 1),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          AppButton(label: 'Open Fair play', variant: AppButtonVariant.outline, height: 50, fontSize: 14, onPressed: () => pushPage<void>(context, const FairnessPage())),
          const SizedBox(height: 24),
          const _ContactCard(),
          const SizedBox(height: 16),
          Text(
            'If gambling is causing problems for you or someone you know, free confidential support is available from your local helpline. In the UK that is GamCare on 0808 8020 133.',
            style: AppText.body(12, color: AppColors.textDim, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard();

  @override
  Widget build(BuildContext context) {
    final signedIn = context.select((AuthBloc b) => b.state.isAuthenticated);
    final s = context.select((SupportCubit c) => c.state);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Still stuck?', style: AppText.body(17, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            signedIn ? 'Send us a message. A real person replies here, and you get a red dot when they do.' : 'Sign in to message our team. You can still email us below.',
            style: AppText.body(13, color: AppColors.textDim, height: 1.45),
          ),
          const SizedBox(height: 14),
          if (signedIn) ...[
            AppButton(label: 'Message support', icon: Icons.chat_bubble_outline_rounded, variant: AppButtonVariant.gold, height: 52, fontSize: 15, onPressed: () => pushPage<void>(context, const NewTicketPage())),
            if (s.tickets.isNotEmpty) ...[
              const SizedBox(height: 10),
              AppButton(
                label: s.unread > 0 ? 'My conversations  ·  ${s.unread} new' : 'My conversations (${s.tickets.length})',
                variant: AppButtonVariant.outline,
                height: 50,
                fontSize: 15,
                onPressed: () => pushPage<void>(context, const TicketsPage()),
              ),
            ],
            const SizedBox(height: 10),
          ],
          AppButton(
            label: 'Copy support email',
            variant: AppButtonVariant.ghost,
            height: 46,
            fontSize: 14,
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: kSupportEmail));
              showToast(context, 'Support email copied: $kSupportEmail');
            },
          ),
        ],
      ),
    );
  }
}
