import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../auth/bloc/auth_bloc.dart';
import '../components/components.dart';

/// E1. Shown while the profile loads. Offers a way out if it takes too long.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late final AnimationController _bar = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  Timer? _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      glowColor: AppColors.purple,
      body: Column(
        children: [
          const Spacer(flex: 3),
          Text('REV', style: AppText.heading(64, letterSpacing: -3, height: .95)),
          Text('GAMES', style: AppText.heading(64, letterSpacing: -3, height: .95, color: AppColors.gold)),
          const SizedBox(height: 12),
          Text('Play for fun. Credits only.', style: AppText.body(14, color: AppColors.textMuted)),
          const Spacer(flex: 3),
          SizedBox(
            width: 160,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 4,
                child: AnimatedBuilder(
                  animation: _bar,
                  builder: (_, __) => Stack(
                    children: [
                      Container(color: AppColors.track),
                      FractionallySizedBox(
                        alignment: Alignment(-1 + 2 * _bar.value, 0),
                        widthFactor: .4,
                        child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: AppColors.gold)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(_slow ? 'Taking longer than usual…' : 'Loading games', style: AppText.body(12, color: AppColors.textDim)),
          if (_slow) ...[
            const SizedBox(height: 12),
            AppButton(
              label: 'Sign out',
              variant: AppButtonVariant.ghost,
              expanded: false,
              height: 44,
              fontSize: 14,
              onPressed: () => context.read<AuthBloc>().add(const AuthSignOutRequested()),
            ),
          ],
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 28),
            child: Text('DEMO VERSION · NO REAL MONEY', style: AppText.label(color: AppColors.textFaint, size: 10)),
          ),
        ],
      ),
    );
  }
}
