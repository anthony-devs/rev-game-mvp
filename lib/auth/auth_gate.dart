import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../home/games_launcher.dart';
import 'bloc/auth_bloc.dart';
import 'pages/login_page.dart';

/// Shows the lobby when signed in and the login screen when not.
/// Rebuilds only when the sign-in status changes.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final signedIn = context.select((AuthBloc b) => b.state.isAuthenticated);
    return signedIn ? const GamesLauncher() : const LoginPage();
  }
}
