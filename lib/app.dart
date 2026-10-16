import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'auth/auth.dart';
import 'components/components.dart';

/// Root widget: provides the auth repository and bloc, and returns to the
/// first screen whenever the player signs in or out.
class RevApp extends StatefulWidget {
  const RevApp({super.key, required this.authRepository});

  final AuthRepository authRepository;

  @override
  State<RevApp> createState() => _RevAppState();
}

class _RevAppState extends State<RevApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<AuthRepository>.value(
      value: widget.authRepository,
      child: BlocProvider(
        create: (context) => AuthBloc(context.read<AuthRepository>()),
        child: BlocListener<AuthBloc, AuthState>(
          listenWhen: (a, b) => a.isAuthenticated != b.isAuthenticated,
          // Close sign up / phone / game pages that are still open on top.
          listener: (context, state) => _navigatorKey.currentState?.popUntil((route) => route.isFirst),
          child: MaterialApp(
            navigatorKey: _navigatorKey,
            title: 'REV GAMES',
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark(useMaterial3: true).copyWith(scaffoldBackgroundColor: AppColors.bg),
            home: const AuthGate(),
          ),
        ),
      ),
    );
  }
}
