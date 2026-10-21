import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';

import '../auth/require_sign_in.dart';
import '../components/components.dart';
import '../core/api/api_client.dart';
import '../components/core/formatters.dart';
import '../games/game_support.dart' show pushPage, showToast;
import 'referral_api.dart';

/// A card inviting players to refer a friend. Shown on the home screen and in the rounds sheet.
class InviteCard extends StatelessWidget {
  const InviteCard({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: () {
        if (!requireSignIn(context)) return;
        pushPage<void>(context, const ReferralPage());
      },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 14 : 18),
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.gold.withValues(alpha: .45)),
        ),
        child: Row(children: [
          Icon(Icons.card_giftcard_rounded, size: 30, color: AppColors.gold),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Invite a friend, get bonus rounds', style: AppText.body(15, weight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('You both get free rounds when they join with your code.', style: AppText.body(12, color: AppColors.textMuted, height: 1.4)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
        ]),
      ),
    );
  }
}

class ReferralPage extends StatefulWidget {
  const ReferralPage({super.key});

  @override
  State<ReferralPage> createState() => _ReferralPageState();
}

class _ReferralPageState extends State<ReferralPage> {
  late final ReferralApi _api = ReferralApi(context.read<ApiClient>());
  final _code = TextEditingController();
  ReferralInfo? _info;
  bool _failed = false;
  bool _applying = false;
  String? _codeError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final i = await _api.info();
      if (mounted) setState(() => _info = i);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  String _message(ReferralInfo i) =>
      'Join me on REV GAMES! Use my code ${i.code} when you sign up and get ${i.friendRounds} free bonus rounds.${i.link.isEmpty ? '' : '\n${i.link}'}';

  Future<void> _share(ReferralInfo i) async {
    AppSound.play(Sfx.tap);
    try {
      await Share.share(_message(i));
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: _message(i)));
      if (mounted) showToast(context, 'Invite copied. Paste it to a friend.');
    }
  }

  Future<void> _copy(ReferralInfo i) async {
    await Clipboard.setData(ClipboardData(text: i.code));
    if (mounted) showToast(context, 'Code copied.');
  }

  Future<void> _apply() async {
    if (_applying) return;
    setState(() {
      _applying = true;
      _codeError = null;
    });
    try {
      final n = await _api.apply(_code.text);
      if (!mounted) return;
      _code.clear();
      showToast(context, '$n bonus rounds added.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _codeError = e.message);
    } catch (_) {
      if (mounted) setState(() => _codeError = "Couldn't add the code. Please try again.");
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = _info;
    return AppScaffold(
      glowColor: AppColors.gold,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, 32),
        children: [
          SubPageBar(title: 'Invite friends', onBack: () => Navigator.of(context).maybePop(), padding: const EdgeInsets.symmetric(vertical: 8)),
          if (i == null && !_failed)
            const Padding(padding: EdgeInsets.only(top: 80), child: Center(child: AppLoader()))
          else if (i == null)
            StatusView(icon: Icons.cloud_off_rounded, title: "Couldn't load this", message: 'Check your connection and try again.', actionLabel: 'Try again', onAction: _load)
          else if (!i.enabled)
            const StatusView(icon: Icons.card_giftcard_rounded, title: 'Invites are paused', message: 'Check back soon.')
          else ...[
            Text('Invite a friend.\nYou both win.', style: AppText.heading(28, letterSpacing: -.8, height: 1.1)),
            const SizedBox(height: 8),
            Text('Your friend gets ${i.friendRounds} bonus rounds when they enter your code. You get ${i.referrerRounds} bonus rounds once they have played ${i.qualifyRounds} rounds.',
                style: AppText.body(14, color: AppColors.textMuted, height: 1.5)),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.line)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('YOUR CODE', style: AppText.label()),
                    const SizedBox(height: 4),
                    Text(i.code, style: AppText.number(28, color: AppColors.gold).copyWith(letterSpacing: 3)),
                  ]),
                ),
                IconSquareButton(icon: Icons.copy_rounded, semanticLabel: 'Copy code', onPressed: () => _copy(i)),
              ]),
            ),
            const SizedBox(height: 12),
            AppButton(label: 'Invite a friend', icon: Icons.ios_share_rounded, variant: AppButtonVariant.gold, height: 54, onPressed: () => _share(i)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: StatTile(label: 'Invited', value: '${i.invited}')),
              const SizedBox(width: 10),
              Expanded(child: StatTile(label: 'Joined & playing', value: '${i.rewarded}', valueColor: AppColors.green)),
              const SizedBox(width: 10),
              Expanded(child: StatTile(label: 'Rounds earned', value: '${i.roundsEarned}', valueColor: AppColors.gold)),
            ]),
            if (i.boostMult != null) ...[
              const SizedBox(height: 12),
              InfoCard(
                title: '${formatMultiplier(i.boostMult!, trim: true)} bonus is active',
                message: 'Your daily coins and referral rounds are multiplied for the next ${_mins(i.boostSecondsLeft)}.',
                icon: Icons.bolt_rounded,
                color: AppColors.gold,
              ),
            ],
            if (i.canApply) ...[
              const SizedBox(height: 24),
              Text('HAVE A FRIEND\'S CODE?', style: AppText.label()),
              const SizedBox(height: 8),
              AppTextField(
                label: 'Referral code',
                hint: 'Enter the code',
                controller: _code,
                errorText: _codeError,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')), LengthLimitingTextInputFormatter(12)],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _apply(),
              ),
              const SizedBox(height: 10),
              AppButton(label: 'Add code', variant: AppButtonVariant.outline, height: 48, loading: _applying, onPressed: _apply),
            ],
            const SizedBox(height: 18),
            Text('You can be rewarded for up to ${i.maxRewards} friends. Bonus rounds are for playing only and have no cash value.',
                style: AppText.body(12, color: AppColors.textDim, height: 1.5)),
          ],
        ],
      ),
    );
  }

  static String _mins(int seconds) {
    final m = (seconds / 60).ceil();
    return m >= 60 ? '${(m / 60).floor()}h ${m % 60}m' : '${m}m';
  }
}
