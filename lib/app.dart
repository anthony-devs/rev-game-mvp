import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'auth/auth.dart';
import 'catalog/catalog_cubit.dart';
import 'session/session_guard.dart';
import 'components/components.dart';
import 'core/api/api_client.dart';
import 'user/user.dart';

/// Root widget: provides the repositories, the API client and the two app-wide blocs
/// ([AuthBloc] and [ProfileCubit]), and returns to the first screen whenever
/// the player signs in or out.
class RevApp extends StatefulWidget {
  const RevApp({super.key, required this.authRepository, required this.userRepository, required this.apiClient});

  final AuthRepository authRepository;
  final UserRepository userRepository;
  final ApiClient apiClient;

  @override
  State<RevApp> createState() => _RevAppState();
}

class _RevAppState extends State<RevApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepository>.value(value: widget.authRepository),
        RepositoryProvider<UserRepository>.value(value: widget.userRepository),
        RepositoryProvider<ApiClient>.value(value: widget.apiClient),
        RepositoryProvider<WalletApi>(create: (context) => WalletApi(context.read<ApiClient>())),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (context) => AuthBloc(context.read<AuthRepository>())),
          BlocProvider(
            create: (context) => ProfileCubit(context.read<UserRepository>(), context.read<WalletApi>())
              ..bind(context.read<AuthBloc>().state.user),
          ),
          BlocProvider(create: (context) => CatalogCubit(context.read<UserRepository>())),
          BlocProvider(create: (context) => SessionGuard(context.read<ProfileCubit>())),
        ],
        child: MultiBlocListener(
          listeners: [
            // Load the right player's data whenever the signed in player changes.
            BlocListener<AuthBloc, AuthState>(
              listenWhen: (a, b) => a.user.id != b.user.id,
              listener: (context, state) {
                context.read<SessionGuard>().reset();
                context.read<ProfileCubit>().bind(state.user);
              },
            ),
            // Close sign up / phone / game pages that are still open on top.
            BlocListener<AuthBloc, AuthState>(
              listenWhen: (a, b) => a.isAuthenticated != b.isAuthenticated,
              listener: (context, state) => _navigatorKey.currentState?.popUntil((route) => route.isFirst),
            ),
          ],
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
