import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../pages/account_restricted_page.dart';
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

    // Banned, suspended, restricted or under review: nothing else is reachable.
    // Staff actions arrive live, so this flips the moment one is applied or lifted.
    final blocked = context.select((ProfileCubit c) => c.state.blocksPlay);
    final adult = context.select((ProfileCubit c) => c.state.user.ageConfirmed);
    return BlocListener<ProfileCubit, ProfileState>(
      // A game or sheet may be open on top: close everything back to this screen.
      listenWhen: (a, b) => !a.blocksPlay && b.blocksPlay,
      listener: (context, _) => Navigator.of(context).popUntil((r) => r.isFirst),
      child: blocked ? const AccountRestrictedPage() : (adult ? const MainShell() : const AgeGatePage()),
    );
  }
}
