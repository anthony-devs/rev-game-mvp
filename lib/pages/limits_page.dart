import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../games/game_support.dart';
import '../model/model.dart';
import '../user/bloc/profile_cubit.dart';
import 'help_page.dart';

/// U2. Reality check, loss limit, highest bet, session time and breaks.
class LimitsPage extends StatefulWidget {
  const LimitsPage({super.key});

  @override
  State<LimitsPage> createState() => _LimitsPageState();
}

class _LimitsPageState extends State<LimitsPage> {
  late PlayLimits _l = context.read<ProfileCubit>().state.limits;
  bool _saving = false;
  bool _dirty = false;

  static const _lossStep = 5000.0;
  static const _betStep = 500.0;

  void _edit(PlayLimits Function(PlayLimits) f) => setState(() {
        _l = f(_l);
        _dirty = true;
      });

  /// `copyWith` cannot clear a value, so limits are rebuilt whole.
  PlayLimits _build({int? reality, int? session, Object? loss = _keep, Object? bet = _keep}) => PlayLimits(
        realityCheckMinutes: reality ?? _l.realityCheckMinutes,
        sessionLimitMinutes: session ?? _l.sessionLimitMinutes,
        maxBetCap: identical(bet, _keep) ? _l.maxBetCap : bet as double?,
        sessionLossLimit: identical(loss, _keep) ? _l.sessionLossLimit : loss as double?,
        coolOffUntil: _l.coolOffUntil,
      );

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<ProfileCubit>().updateLimits(_l);
      if (!mounted) return;
      showToast(context, 'Limits saved');
      setState(() => _dirty = false);
      Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) showToast(context, 'Could not save. Check your connection.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _break(Duration d, String label) async {
    final ok = await showAppDialog<bool>(
      context,
      AppDialogCard(
        icon: Icons.self_improvement_rounded,
        iconColor: AppColors.blue,
        title: 'Take a $label break?',
        message: 'You will not be able to play any game until the break ends. This cannot be undone early.',
        primaryLabel: 'Start break',
        onPrimary: () => Navigator.of(context).pop(true),
        secondaryLabel: 'Cancel',
        onSecondary: () => Navigator.of(context).pop(false),
      ),
      dismissible: true,
    );
    if (ok != true || !mounted) return;
    final next = PlayLimits(
      realityCheckMinutes: _l.realityCheckMinutes,
      sessionLimitMinutes: _l.sessionLimitMinutes,
      maxBetCap: _l.maxBetCap,
      sessionLossLimit: _l.sessionLossLimit,
      coolOffUntil: DateTime.now().add(d),
    );
    try {
      await context.read<ProfileCubit>().updateLimits(next);
      if (!mounted) return;
      showToast(context, 'Break started. See you soon.');
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (_) {
      if (mounted) showToast(context, 'Could not start the break. Check your connection.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _l;
    final cooling = l.isCoolingOff(DateTime.now());
    final loss = l.sessionLossLimit;
    final bet = l.maxBetCap;
    final reality = l.realityCheckMinutes;

    return AppScaffold(
      glowColor: AppColors.blue,
      body: Column(
        children: [
          SubPageBar(title: 'Play limits', onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 4, AppSpacing.screen, 24),
              children: [
                Text('Stay in control. These tools work even though this is a demo.', style: AppText.body(14, color: AppColors.textMuted, height: 1.5)),
                const SizedBox(height: 16),
                if (cooling)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: InfoCard(title: 'Break active', message: 'You are taking a break. Games open again when it ends.', icon: Icons.self_improvement_rounded, color: AppColors.blue),
                  ),
                _Card(
                  title: 'Reality check reminder',
                  child: SegmentedToggle<int>(
                    height: 44,
                    options: const [
                      SegmentOption(value: 0, label: 'Off'),
                      SegmentOption(value: 15, label: '15 min'),
                      SegmentOption(value: 30, label: '30 min'),
                      SegmentOption(value: 60, label: '60 min'),
                    ],
                    selected: [0, 15, 30, 60].contains(reality) ? reality : 60,
                    onChanged: (v) => _edit((_) => _build(reality: v)),
                  ),
                ),
                const SizedBox(height: 12),
                _Card(
                  title: 'Loss limit per session',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StepperField(
                        label: 'Credits',
                        valueText: loss == null || loss <= 0 ? 'Off' : formatCredits(loss, decimals: 0),
                        active: loss != null && loss > 0,
                        onToggle: (on) => _edit((_) => _build(loss: on ? 20000.0 : null)),
                        onMinus: loss == null || loss <= 0 ? null : () => _edit((_) => _build(loss: (loss - _lossStep).clamp(_lossStep, 1e9))),
                        onPlus: loss == null || loss <= 0 ? null : () => _edit((_) => _build(loss: loss + _lossStep)),
                      ),
                      const SizedBox(height: 8),
                      Text('Play pauses when you have lost this much in one session.', style: AppText.body(12, color: AppColors.textDim)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Card(
                  title: 'Highest bet',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StepperField(
                        label: 'Credits per round',
                        valueText: bet == null || bet <= 0 ? 'Off' : formatCredits(bet, decimals: 0),
                        active: bet != null && bet > 0,
                        onToggle: (on) => _edit((_) => _build(bet: on ? 1000.0 : null)),
                        onMinus: bet == null || bet <= 0 ? null : () => _edit((_) => _build(bet: (bet - _betStep).clamp(10.0, 1e9))),
                        onPlus: bet == null || bet <= 0 ? null : () => _edit((_) => _build(bet: bet + _betStep)),
                      ),
                      const SizedBox(height: 8),
                      Text('No bet can go above this, in any game.', style: AppText.body(12, color: AppColors.textDim)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Card(
                  title: 'Session time limit',
                  child: SegmentedToggle<int>(
                    height: 44,
                    options: const [
                      SegmentOption(value: 0, label: 'Off'),
                      SegmentOption(value: 30, label: '30 min'),
                      SegmentOption(value: 60, label: '1 hour'),
                      SegmentOption(value: 120, label: '2 hours'),
                    ],
                    selected: [0, 30, 60, 120].contains(l.sessionLimitMinutes) ? l.sessionLimitMinutes : 0,
                    onChanged: (v) => _edit((_) => _build(session: v)),
                  ),
                ),
                const SizedBox(height: 12),
                _Card(
                  title: 'Take a break',
                  child: Row(
                    children: [
                      Expanded(child: AppButton(label: '15 min', variant: AppButtonVariant.outline, height: 46, fontSize: 14, onPressed: () => _break(const Duration(minutes: 15), '15 minute'))),
                      const SizedBox(width: 8),
                      Expanded(child: AppButton(label: '1 hour', variant: AppButtonVariant.outline, height: 46, fontSize: 14, onPressed: () => _break(const Duration(hours: 1), '1 hour'))),
                      const SizedBox(width: 8),
                      Expanded(child: AppButton(label: '24 hours', variant: AppButtonVariant.outline, height: 46, fontSize: 14, onPressed: () => _break(const Duration(hours: 24), '24 hour'))),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: .08), borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.blue.withValues(alpha: .3))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Need to talk to someone?', style: AppText.body(16, weight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text('If gambling is causing problems for you or someone you know, free confidential support is available.', style: AppText.body(13, color: AppColors.textMuted, height: 1.5)),
                      const SizedBox(height: 12),
                      AppButton(label: 'Find support', variant: AppButtonVariant.outline, height: 46, fontSize: 14, onPressed: () => pushPage<void>(context, const HelpPage())),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).padding.bottom),
            child: AppButton(label: 'Save limits', variant: AppButtonVariant.gold, loading: _saving, onPressed: (_dirty && !_saving) ? _save : null),
          ),
        ],
      ),
    );
  }
}

const Object _keep = Object();

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppText.body(15, weight: FontWeight.w700)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
