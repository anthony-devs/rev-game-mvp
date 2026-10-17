import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../core/api/api_client.dart';
import '../games/game_support.dart';
import '../model/model.dart';
import '../user/bloc/profile_cubit.dart';
import '../user/data/user_repository.dart';
import '../user/data/wallet_api.dart';
import 'help_page.dart';
import 'round_format.dart';
import 'system_pages.dart';
import '../support/new_ticket_page.dart';
import '../support/support_models.dart';

/// G7. Verify a round, and manage the seeds behind every result.
///
/// With a [roundId] it shows that round's check. Without one it only shows
/// your seeds (open it from the shield icon in a game).
class FairnessPage extends StatefulWidget {
  const FairnessPage({super.key, this.roundId});

  final String? roundId;

  @override
  State<FairnessPage> createState() => _FairnessPageState();
}

class _FairnessPageState extends State<FairnessPage> {
  late final WalletApi _api = context.read<WalletApi>();

  Future<VerifyResult>? _verify;
  Future<GameRound?>? _round;
  Future<FairnessState>? _seeds;
  bool _rotating = false;
  bool _advanced = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final id = widget.roundId;
    if (id != null) {
      _verify = _api.verify(id);
      final uid = context.read<ProfileCubit>().state.dataId;
      _round = context.read<UserRepository>().round(uid, id);
    }
    _seeds = _api.fairness();
  }

  Future<void> _rotate({String? clientSeed}) async {
    setState(() => _rotating = true);
    try {
      final r = await _api.rotateSeed(clientSeed: clientSeed);
      AppSound.play(Sfx.coin);
      if (!mounted) return;
      setState(() {
        _seeds = Future.value(r.current);
        if (widget.roundId != null) _verify = _api.verify(widget.roundId!);
      });
      showToast(context, r.revealed == null ? 'New seed ready' : 'Old seed revealed. New seed ready.');
    } catch (e) {
      AppSound.play(Sfx.error);
      if (mounted) showToast(context, failText(e), error: true);
    } finally {
      if (mounted) setState(() => _rotating = false);
    }
  }

  Future<void> _editClientSeed(String current) async {
    final c = TextEditingController(text: current);
    final seed = await showAppBottomSheet<String>(
      context,
      title: 'Set your client seed',
      child: Column(
        children: [
          AppTextField(label: 'Client seed', hint: '1 to 32 characters', controller: c, autofocus: true),
          const SizedBox(height: 8),
          Text('Changing it also rotates the server seed, so your old seed is revealed.', style: AppText.body(12, color: AppColors.textDim)),
          const SizedBox(height: 16),
          Builder(builder: (ctx) => AppButton(label: 'Save and rotate', onPressed: () => Navigator.of(ctx).pop(c.text.trim()))),
        ],
      ),
    );
    c.dispose();
    if (seed != null && seed.isNotEmpty) _rotate(clientSeed: seed);
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.select((ProfileCubit c) => c.state.dataId);
    return AppScaffold(
      glowColor: AppColors.green,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, 32),
        children: [
          SubPageBar(
            title: widget.roundId == null ? 'Fair play' : 'Round check',
            onBack: () => Navigator.of(context).maybePop(),
            padding: const EdgeInsets.symmetric(vertical: 8),
          ),
          if (widget.roundId == null) ...[
            const _FairIntro(),
            const SizedBox(height: 20),
          ],
          if (widget.roundId != null) ...[
            FutureBuilder<VerifyResult>(
              future: _verify,
              builder: (context, snap) {
                if (snap.hasError) return _error(snap.error!, () => setState(_load));
                if (!snap.hasData) return const Column(children: [SkeletonBox(height: 84, radius: 20), SizedBox(height: 12), SkeletonBox(height: 260, radius: 20)]);
                return _RoundCheck(result: snap.data!, round: _round, showTech: _advanced, rotating: _rotating, onRotate: () => _rotate(), onAgain: () => setState(() => _verify = _api.verify(widget.roundId!)));
              },
            ),
            const SizedBox(height: 24),
          ],
          _AdvancedToggle(open: _advanced, onTap: () => setState(() => _advanced = !_advanced)),
          if (_advanced) ...[
          const SizedBox(height: 14),
          Text('YOUR SEEDS', style: AppText.label()),
          const SizedBox(height: 10),
          FutureBuilder<FairnessState>(
            future: _seeds,
            builder: (context, snap) {
              if (snap.hasError) return _error(snap.error!, () => setState(_load));
              if (!snap.hasData) return const SkeletonBox(height: 200, radius: 20);
              final s = snap.data!;
              return Column(
                children: [
                  _Field(label: 'Server seed hash (shown before you play)', value: s.serverSeedHash, mono: true),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _Field(label: 'Client seed', value: s.clientSeed, mono: true, onTap: () => _editClientSeed(s.clientSeed))),
                      const SizedBox(width: 10),
                      Expanded(child: _Field(label: 'Next nonce', value: '${s.nonce}', mono: true)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  AppButton(label: 'Rotate seed', variant: AppButtonVariant.outline, height: 52, loading: _rotating, onPressed: _rotating ? null : () => _rotate()),
                  const SizedBox(height: 8),
                  Text(
                    'Rotating reveals the old server seed so every round that used it can be checked. Not possible while a crash round or blackjack hand is open.',
                    style: AppText.body(12, color: AppColors.textDim, height: 1.5),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Text('REVEALED SEEDS', style: AppText.label()),
          const SizedBox(height: 10),
          if (uid.isNotEmpty) _Revealed(uid: uid),
          ],
          const SizedBox(height: 20),
          if (widget.roundId != null) ...[
            AppButton(
              label: 'Report a problem with this round',
              variant: AppButtonVariant.outline,
              height: 48,
              fontSize: 14,
              onPressed: () => pushPage<void>(
                context,
                NewTicketPage(
                  category: TicketCategory.fairness,
                  subject: 'Problem with a round',
                  message: 'Round id: ${widget.roundId}\n\nWhat looked wrong: ',
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          AppButton(label: 'How verification works', variant: AppButtonVariant.ghost, height: 48, fontSize: 14, onPressed: () => pushPage<void>(context, const HelpPage(openFairness: true))),
        ],
      ),
    );
  }

  Widget _error(Object e, VoidCallback retry) {
    if (e is ApiException && e.isNetwork) return OfflineView(onRetry: retry, error: e);
    return InfoCard(title: 'Could not check', message: failText(e), icon: Icons.error_outline_rounded, color: AppColors.loss);
  }
}

class _RoundCheck extends StatelessWidget {
  const _RoundCheck({required this.result, required this.round, required this.showTech, required this.rotating, required this.onRotate, required this.onAgain});

  final VerifyResult result;
  final Future<GameRound?>? round;
  final bool showTech;
  final bool rotating;
  final VoidCallback onRotate;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final Color tone;
    final IconData icon;
    final String title;
    final String sub;
    if (r.isVerified) {
      tone = AppColors.green;
      icon = Icons.verified_rounded;
      title = 'Round verified';
      sub = 'This result was locked in before you played and has not been changed.';
    } else if (r.isPending) {
      tone = AppColors.gold;
      icon = Icons.hourglass_top_rounded;
      title = 'Ready to be checked';
      sub = 'Refresh your fairness code to open this round for checking.';
    } else {
      tone = AppColors.loss;
      icon = Icons.gpp_bad_rounded;
      title = 'Does not match';
      sub = 'This round failed the check. Please contact support.';
    }
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: tone.withValues(alpha: .1), borderRadius: BorderRadius.circular(20), border: Border.all(color: tone.withValues(alpha: .5))),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(shape: BoxShape.circle, color: tone.withValues(alpha: .15)),
                child: Icon(icon, color: tone, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.body(17, weight: FontWeight.w700, color: tone)),
                    const SizedBox(height: 2),
                    Text(sub, style: AppText.body(12, color: AppColors.textMuted, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<GameRound?>(
          future: round,
          builder: (context, snap) {
            final g = snap.data;
            final gameName = g?.game.title ?? r.game;
            return _Field(label: 'Game · Round', value: g == null ? gameName : '$gameName · ${g.summary}');
          },
        ),
        if (showTech) ...[
        const SizedBox(height: 10),
        _Field(label: 'Server seed hash (shown before the round)', value: r.serverSeedHash, mono: true),
        const SizedBox(height: 10),
        _Field(
          label: 'Server seed (revealed after the round)',
          value: r.serverSeed ?? 'Hidden until you rotate your seed',
          mono: r.serverSeed != null,
          dim: r.serverSeed == null,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _Field(label: 'Client seed', value: r.clientSeed, mono: true)),
            const SizedBox(width: 10),
            Expanded(child: _Field(label: 'Nonce', value: '${r.nonce}', mono: true)),
          ],
        ),
        ],
        if (r.hashMatches != null || r.outcomeMatches != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _Check(label: 'Locked in advance', ok: r.hashMatches)),
              const SizedBox(width: 10),
              Expanded(child: _Check(label: 'Result matches', ok: r.outcomeMatches)),
            ],
          ),
        ],
        const SizedBox(height: 14),
        if (r.isPending)
          AppButton(label: 'Refresh and verify', variant: AppButtonVariant.gold, loading: rotating, onPressed: rotating ? null : onRotate)
        else
          AppButton(label: 'Check again', variant: AppButtonVariant.success, onPressed: onAgain),
      ],
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.label, required this.ok});
  final String label;
  final bool? ok;

  @override
  Widget build(BuildContext context) {
    final c = ok == null ? AppColors.textDim : (ok! ? AppColors.green : AppColors.loss);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(color: c.withValues(alpha: .08), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withValues(alpha: .35))),
      child: Row(
        children: [
          Icon(ok == null ? Icons.remove_rounded : (ok! ? Icons.check_circle_rounded : Icons.cancel_rounded), size: 18, color: c),
          const SizedBox(width: 8),
          Text(label, style: AppText.body(13, weight: FontWeight.w600, color: c)),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.mono = false, this.dim = false, this.onTap});

  final String label;
  final String value;
  final bool mono;
  final bool dim;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap ?? () {
        Clipboard.setData(ClipboardData(text: value));
        showToast(context, 'Copied');
      },
      scale: .99,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppText.body(11, weight: FontWeight.w600, color: AppColors.textDim)),
            const SizedBox(height: 6),
            Text(
              value.isEmpty ? '-' : value,
              style: mono ? AppText.mono(12, color: dim ? AppColors.textDim : AppColors.textSoft) : AppText.body(14, weight: FontWeight.w600, color: dim ? AppColors.textDim : AppColors.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _Revealed extends StatelessWidget {
  const _Revealed({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RevealedSeedDoc>>(
      stream: context.read<UserRepository>().watchSeedHistory(uid),
      builder: (context, snap) {
        final list = snap.data ?? const <RevealedSeedDoc>[];
        if (list.isEmpty) {
          return InfoCard(message: 'Seeds you rotate away show up here, so you can check old rounds any time.', icon: Icons.key_outlined, color: AppColors.textDim);
        }
        return Column(
          children: [
            for (final s in list) ...[
              _Field(label: 'Hash ${s.serverSeedHash.substring(0, s.serverSeedHash.length < 12 ? s.serverSeedHash.length : 12)}…  ·  ${s.nonceEnd} rounds', value: s.serverSeed, mono: true),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

/// What fairness means for a player, in plain words. The technical part lives under "Advanced".
class _FairIntro extends StatelessWidget {
  const _FairIntro();

  @override
  Widget build(BuildContext context) {
    Widget step(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.green.withValues(alpha: .12)),
                child: Icon(icon, size: 20, color: AppColors.green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.body(14, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(body, style: AppText.body(13, color: AppColors.textMuted, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_rounded, color: AppColors.green, size: 26),
              const SizedBox(width: 10),
              Expanded(child: Text('Every round is fair, and you can check it', style: AppText.body(17, weight: FontWeight.w800, height: 1.2))),
            ],
          ),
          step(Icons.lock_outline_rounded, 'Locked before you play', 'The result is decided and sealed before you place a bet. Nobody can change it afterwards, including us.'),
          step(Icons.fact_check_outlined, 'Checked after every round', 'Open any round in History and tap it to see the proof that the result is the one that was sealed.'),
          step(Icons.balance_rounded, 'Same rules for everyone', 'Payout tables are published in each game, under the paytable.'),
        ],
      ),
    );
  }
}

class _AdvancedToggle extends StatelessWidget {
  const _AdvancedToggle({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      scale: .99,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
        child: Row(
          children: [
            Expanded(child: Text('Advanced: seeds and technical details', style: AppText.body(14, weight: FontWeight.w600, color: AppColors.textSoft))),
            Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.textDim),
          ],
        ),
      ),
    );
  }
}
