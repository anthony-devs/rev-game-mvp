import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/components.dart';
import '../games/game_support.dart';
import 'fairness_page.dart';

/// Where players write to. Replace before release.
const String kSupportEmail = 'support@revgames.example';

class _Faq {
  const _Faq(this.q, this.a, {this.key = ''});
  final String q;
  final String a;
  final String key;
}

const List<_Faq> _faqs = [
  _Faq('Are credits real money?',
      'No. Credits are virtual. You cannot buy, sell, deposit or withdraw them, and they have no cash value. REV GAMES is a demo for fun only.'),
  _Faq('How do I get more credits?',
      'Open the wallet and tap Get demo credits. You can claim a daily reward every 24 hours. Claim on consecutive days to build a streak: days 1 to 7 pay 1,000, 1,000, 1,500, 2,000, 2,500, 3,000 and 10,000. You can also reset your balance back to 10,000 at any time.'),
  _Faq('How are results decided?',
      'Every result is decided on our server before you see it, using a random number generator that is tied to a seed we commit to in advance. The app only shows the result, it never decides it.'),
  _Faq('How do I verify a round?',
      'Open Game history and tap a round, or tap the shield icon in a game. We publish the hash of the server seed before you play. After you rotate your seed we reveal the old one, and the check hashes it and replays the round. If it matches, the result was fixed before you bet.',
      key: 'fair'),
  _Faq('What does RTP mean?',
      'Return to player. A 96% RTP means that over a very long time the game pays back 96 credits for every 100 bet. A single session can be far above or below that.'),
  _Faq('How does the daily streak work?',
      'Claim again within 48 hours of your last claim and the streak grows by one day. Miss that window and it starts again from day 1.'),
  _Faq('How do play limits work?',
      'In Settings, open Play limits. You can turn on reality check reminders, a loss limit per session, a highest bet, or take a break. These are set by you, and they apply to every game.'),
  _Faq('How do I delete my account?',
      'Open Settings, then your profile, then Delete account. This permanently removes your profile, credits, level and history.'),
];

/// U3. Frequently asked questions and a way to contact support.
class HelpPage extends StatefulWidget {
  const HelpPage({super.key, this.openFairness = false});

  /// Start with the "How do I verify a round?" answer open.
  final bool openFairness;

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final list = [for (final f in _faqs) if (q.isEmpty || f.q.toLowerCase().contains(q) || f.a.toLowerCase().contains(q)) f];
    return AppScaffold(
      glowColor: AppColors.blue,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, 32),
        children: [
          SubPageBar(title: 'Help Centre', onBack: () => Navigator.of(context).maybePop(), padding: const EdgeInsets.symmetric(vertical: 8)),
          const SizedBox(height: 8),
          SearchField(hint: 'Search help', onChanged: (v) => setState(() => _query = v)),
          const SizedBox(height: 16),
          if (list.isEmpty)
            const InfoCard(title: 'No answers found', message: 'Try other words, or contact support below.')
          else
            ListGroup(
              children: [
                for (final f in list)
                  FaqTile(
                    key: ValueKey('${f.q}$q'),
                    question: f.q,
                    answer: f.a,
                    initiallyExpanded: (widget.openFairness && f.key == 'fair') || (q.isNotEmpty && list.length == 1),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          AppButton(label: 'Open fairness and seeds', variant: AppButtonVariant.outline, height: 50, fontSize: 14, onPressed: () => pushPage<void>(context, const FairnessPage())),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.line)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Still stuck?', style: AppText.body(17, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Our team replies within one working day.', style: AppText.body(13, color: AppColors.textDim)),
                const SizedBox(height: 14),
                AppButton(
                  label: 'Contact support',
                  variant: AppButtonVariant.outline,
                  height: 50,
                  fontSize: 15,
                  onPressed: () {
                    Clipboard.setData(const ClipboardData(text: kSupportEmail));
                    showToast(context, 'Support email copied: $kSupportEmail');
                  },
                ),
              ],
            ),
          ),
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
