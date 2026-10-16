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

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final id = widget.roundId;
    if (id != null) {
      _verify = _api.verify(id);
      final uid = context.read<ProfileCubit>().state.user.id;
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
    final uid = context.select((ProfileCubit c) => c.state.user.id);
    return AppScaffold(
      glowColor: AppColors.green,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, 32),
        children: [
          SubPageBar(
            title: widget.roundId == null ? 'Provably fair' : 'Verify a round',
            onBack: () => Navigator.of(context).maybePop(),
            padding: const EdgeInsets.symmetric(vertical: 8),
          ),
          if (widget.roundId != null) ...[
            FutureBuilder<VerifyResult>(
              future: _verify,
              builder: (context, snap) {
                if (snap.hasError) return _error(snap.error!, () => setState(_load));
                if (!snap.hasData) return const Column(children: [SkeletonBox(height: 84, radius: 20), SizedBox(height: 12), SkeletonBox(height: 260, radius: 20)]);
                return _RoundCheck(result: snap.data!, round: _round, rotating: _rotating, onRotate: () => _rotate(), onAgain: () => setState(() => _verify = _api.verify(widget.roundId!)));
              },
            ),
            const SizedBox(height: 24),
          ],
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
                    'Rotating reveals the old server seed so you can check every round that used it. Not possible while a crash round or blackjack hand is open.',
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
          const SizedBox(height: 20),
          AppButton(label: 'How verification works', variant: AppButtonVariant.ghost, height: 48, fontSize: 14, onPressed: () => pushPage<void>(context, const HelpPage(openFairness: true))),
        ],
      ),
    );
  }

  Widget _error(Object e, VoidCallback retry) {
    if (e is ApiException && e.isNetwork) return OfflineView(onRetry: retry);
    return InfoCard(title: 'Could not check', message: failText(e), icon: Icons.error_outline_rounded, color: AppColors.loss);
  }
}

class _RoundCheck extends StatelessWidget {
  const _RoundCheck({required this.result, required this.round, required this.rotating, required this.onRotate, required this.onAgain});

  final VerifyResult result;
  final Future<GameRound?>? round;
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
      sub = 'The result matches the committed seed.';
    } else if (r.isPending) {
      tone = AppColors.gold;
      icon = Icons.hourglass_top_rounded;
      title = 'Waiting for the seed';
      sub = 'The server seed is revealed when you rotate. Rotate now to check this round.';
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
        if (r.hashMatches != null || r.outcomeMatches != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _Check(label: 'Seed hash', ok: r.hashMatches)),
              const SizedBox(width: 10),
              Expanded(child: _Check(label: 'Outcome', ok: r.outcomeMatches)),
            ],
          ),
        ],
        const SizedBox(height: 14),
        if (r.isPending)
          AppButton(label: 'Rotate seed to reveal', variant: AppButtonVariant.gold, loading: rotating, onPressed: rotating ? null : onRotate)
        else
          AppButton(label: 'VERIFY AGAIN', variant: AppButtonVariant.success, onPressed: onAgain),
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
          return const InfoCard(message: 'Seeds you rotate away show up here, so you can check old rounds any time.', icon: Icons.key_outlined, color: AppColors.textDim);
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
