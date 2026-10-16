import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../pages/splash_page.dart';
import '../shell/main_shell.dart';
import '../user/bloc/profile_cubit.dart';
import '../user/pages/age_gate_page.dart';
import 'bloc/auth_bloc.dart';
import 'pages/login_page.dart';

/// Picks the screen: sign in, splash (loading), age check, or the app.
/// Rebuilds only when one of those answers changes.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final signedIn = context.select((AuthBloc b) => b.state.isAuthenticated);
    if (!signedIn) return const LoginPage();

    final ready = context.select((ProfileCubit c) => c.state.profileReady);
    if (!ready) return const SplashPage();

    final adult = context.select((ProfileCubit c) => c.state.user.ageConfirmed);
    return adult ? const MainShell() : const AgeGatePage();
  }
}
