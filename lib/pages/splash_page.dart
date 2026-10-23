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

class _SplashPageState extends State<SplashPage> {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      glowColor: AppColors.purple,
      body: Column(
        children: [
          const Spacer(flex: 3),
          const RevWordmark(markSize: 44, textSize: 26),
          const Spacer(flex: 3),
          const AppLoader(size: 40),
          const SizedBox(height: 14),
          if (_slow) ...[
            Text('Taking longer than usual…', style: AppText.body(12, color: AppColors.textDim)),
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
        ],
      ),
    );
  }
}
