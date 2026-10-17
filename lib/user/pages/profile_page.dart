import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../auth/data/auth_validators.dart';
import '../../components/components.dart';
import '../../games/game_support.dart';
import '../../pages/round_format.dart';
import '../bloc/profile_cubit.dart';

/// The player's profile. Sign out and Delete account live here and only here.
// Set while the delete flow is open, so a second tap can't start it twice.
bool _deleting = false;

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.select((ProfileCubit c) => c.state.user);
    final progress = context.select((ProfileCubit c) => c.state.progress);

    return AppScaffold(
      glowColor: AppColors.purple,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.screen, 0, AppSpacing.screen, 32),
        children: [
          SubPageBar(title: 'Profile', onBack: () => Navigator.of(context).maybePop(), padding: const EdgeInsets.symmetric(vertical: 8)),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.line),
                ),
                child: Text(user.initial, style: AppText.heading(28, color: AppColors.gold, letterSpacing: 0)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.heading(22, letterSpacing: -0.5)),
                    const SizedBox(height: 2),
                    Text(
                      user.isAnonymous ? 'Guest account' : (user.email ?? 'Signed in'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body(13, color: AppColors.textDim),
                    ),
                  ],
                ),
              ),
              IconSquareButton(icon: Icons.edit_outlined, semanticLabel: 'Change name', onPressed: () => _rename(context)),
            ],
          ),
          const SizedBox(height: 20),
          LevelProgressCard(
            level: progress.level,
            title: levelTitle(progress.level),
            xp: progress.xp,
            xpMax: progress.xpForNext,
            streakDays: progress.streakDays,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: StatTile(label: 'Rounds', value: formatCredits(progress.totalRounds, decimals: 0))),
              const SizedBox(width: 10),
              Expanded(child: StatTile(label: 'Wins', value: formatCredits(progress.totalWins, decimals: 0), valueColor: AppColors.green)),
              const SizedBox(width: 10),
              Expanded(child: StatTile(label: 'Win rate', value: '${(progress.winRate * 100).round()}%')),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: StatTile(label: 'Biggest win', value: formatCredits(progress.biggestWin, decimals: 0), valueColor: AppColors.gold)),
              const SizedBox(width: 10),
              Expanded(child: StatTile(label: 'Best multiplier', value: progress.bestMultiplier <= 0 ? '-' : formatMultiplier(progress.bestMultiplier, trim: true), valueColor: AppColors.gold)),
            ],
          ),
          if (user.isAnonymous) ...[
            const SizedBox(height: 16),
            InfoCard(
              title: 'You are playing as a guest',
              message: 'Your credits and history are tied to this device. If you sign out as a guest you cannot get this account back.',
              icon: Icons.person_outline_rounded,
              color: AppColors.gold,
            ),
          ],
          const SizedBox(height: 28),
          Text('ACCOUNT', style: AppText.label()),
          const SizedBox(height: 10),
          AppButton(
            label: 'Sign out',
            variant: AppButtonVariant.outline,
            icon: Icons.logout_rounded,
            onPressed: () => _signOut(context, guest: user.isAnonymous),
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Delete account',
            variant: AppButtonVariant.danger,
            icon: Icons.delete_outline_rounded,
            onPressed: () => _delete(context),
          ),
          const SizedBox(height: 8),
          Text(
            'Deleting removes your profile, credits, level and game history for good.',
            textAlign: TextAlign.center,
            style: AppText.body(12, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context, {required bool guest}) async {
    if (guest) {
      final ok = await showAppDialog<bool>(
        context,
        AppDialogCard(
          icon: Icons.logout_rounded,
          title: 'Sign out as a guest?',
          message: 'Guest accounts cannot be signed back in to. Your credits and history on this account will be lost to you.',
          primaryLabel: 'Sign out',
          onPrimary: () => Navigator.of(context).pop(true),
          secondaryLabel: 'Stay',
          onSecondary: () => Navigator.of(context).pop(false),
        ),
        dismissible: true,
      );
      if (ok != true || !context.mounted) return;
    }
    Navigator.of(context).popUntil((r) => r.isFirst);
    context.read<AuthBloc>().add(const AuthSignOutRequested());
  }

  Future<void> _delete(BuildContext context) async {
    if (_deleting) return;
    _deleting = true;
    final confirmed = await showAppDialog<bool>(context, const _DeleteDialog(), dismissible: true);
    if (confirmed != true || !context.mounted) {
      _deleting = false;
      return;
    }

    final cubit = context.read<ProfileCubit>();
    final auth = context.read<AuthBloc>();
    final nav = Navigator.of(context, rootNavigator: true);
    // Block the screen while the server removes everything.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .8),
      builder: (_) => PopScope(canPop: false, child: Center(child: AppLoader())),
    );
    try {
      await cubit.deleteAccount();
      nav.popUntil((r) => r.isFirst);
      auth.add(const AuthSignOutRequested());
    } catch (e) {
      _deleting = false;
      nav.pop(); // the progress dialog
      if (context.mounted) showToast(context, ProfileCubit.errorText(e), error: true);
    }
  }

  void _rename(BuildContext context) {
    final cubit = context.read<ProfileCubit>();
    final controller = TextEditingController(text: cubit.state.user.displayName);
    showAppBottomSheet<void>(
      context,
      title: 'Your name',
      child: _RenameForm(controller: controller, cubit: cubit),
    ).whenComplete(controller.dispose);
  }
}

/// Asks the player to type DELETE before the account goes.
class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog();

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _c.text.trim().toUpperCase() == 'DELETE';
    return Container(
      width: 340,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AppColors.sheet, borderRadius: BorderRadius.circular(28), border: Border.all(color: AppColors.loss.withValues(alpha: .5))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.loss.withValues(alpha: .12), border: Border.all(color: AppColors.loss.withValues(alpha: .5))),
            child: Icon(Icons.delete_forever_rounded, size: 30, color: AppColors.loss),
          ),
          const SizedBox(height: 18),
          Text('Delete your account?', textAlign: TextAlign.center, style: AppText.body(22, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'This permanently deletes your profile, credits, level and game history. It cannot be undone.',
            textAlign: TextAlign.center,
            style: AppText.body(14, color: AppColors.textMuted, height: 1.5),
          ),
          const SizedBox(height: 16),
          AppTextField(label: 'Type DELETE to confirm', controller: _c, onChanged: (_) => setState(() {}), textInputAction: TextInputAction.done),
          const SizedBox(height: 20),
          AppButton(label: 'Delete account', variant: AppButtonVariant.danger, onPressed: ok ? () => Navigator.of(context).pop(true) : null),
          const SizedBox(height: 10),
          AppButton(label: 'Keep my account', variant: AppButtonVariant.outline, height: 52, onPressed: () => Navigator.of(context).pop(false)),
        ],
      ),
    );
  }
}

class _RenameForm extends StatefulWidget {
  const _RenameForm({required this.controller, required this.cubit});

  final TextEditingController controller;
  final ProfileCubit cubit;

  @override
  State<_RenameForm> createState() => _RenameFormState();
}

class _RenameFormState extends State<_RenameForm> {
  String? _error;
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return; // a double tap must not pop twice
    final error = AuthValidators.name(widget.controller.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    _saving = true;
    Navigator.of(context).pop();
    try {
      await widget.cubit.rename(widget.controller.text);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppTextField(
          label: 'Display name',
          controller: widget.controller,
          errorText: _error,
          textInputAction: TextInputAction.done,
          autofocus: true,
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 20),
        AppButton(label: 'Save', onPressed: _save),
      ],
    );
  }
}
