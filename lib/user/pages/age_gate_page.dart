import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/bloc/auth_bloc.dart';
import '../../components/components.dart';
import '../bloc/profile_cubit.dart';

/// Shown once after sign up. The player must be 18 or older to continue.
class AgeGatePage extends StatefulWidget {
  const AgeGatePage({super.key});

  @override
  State<AgeGatePage> createState() => _AgeGatePageState();
}

class _AgeGatePageState extends State<AgeGatePage> {
  bool _busy = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ProfileCubit>().confirmAge();
      // AuthGate moves on by itself once the profile says ageConfirmed.
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not save that. Check your connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      glowColor: AppColors.purple,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 12, AppSpacing.xl, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Align(alignment: Alignment.centerLeft, child: Text('REV GAMES', style: AppText.heading(22, letterSpacing: -1))),
            const Spacer(),
            Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.gold.withValues(alpha: .1), border: Border.all(color: AppColors.gold, width: 2)),
              child: Text('18+', style: AppText.heading(32, color: AppColors.gold, letterSpacing: -1)),
            ),
            const SizedBox(height: 24),
            Text('Are you 18 or older?', textAlign: TextAlign.center, style: AppText.heading(28, letterSpacing: -1)),
            const SizedBox(height: 12),
            Text(
              'This is a demo that uses virtual credits only. You must be 18 or over to play.',
              textAlign: TextAlign.center,
              style: AppText.body(14, color: AppColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 22),
            const _Bullet('No real money, deposits or withdrawals'),
            const _Bullet('Credits have no cash value'),
            const _Bullet('Every result is decided on the server'),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center, style: AppText.body(13, color: AppColors.loss)),
            ],
            const Spacer(),
            AppButton(label: 'Yes, I am 18 or older', variant: AppButtonVariant.gold, loading: _busy, onPressed: _busy ? null : _confirm),
            const SizedBox(height: 10),
            AppButton(
              label: 'No, take me out',
              variant: AppButtonVariant.outline,
              height: 52,
              onPressed: _busy ? null : () => context.read<AuthBloc>().add(const AuthSignOutRequested()),
            ),
            const SizedBox(height: 14),
            Text('By continuing you accept the Terms and Privacy Policy.', textAlign: TextAlign.center, style: AppText.body(11, color: AppColors.textFaint)),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.green)),
          const SizedBox(width: 10),
          Flexible(child: Text(text, style: AppText.body(13, weight: FontWeight.w600, color: AppColors.textSoft))),
        ],
      ),
    );
  }
}
