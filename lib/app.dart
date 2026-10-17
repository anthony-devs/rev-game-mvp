import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'live/live_api.dart';
import 'live/live_cubit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'auth/auth.dart';
import 'catalog/catalog_cubit.dart';
import 'session/session_guard.dart';
import 'support/support_api.dart';
import 'support/support_cubit.dart';
import 'theme/theme_cubit.dart';
import 'components/components.dart';
import 'core/api/api_client.dart';
import 'user/user.dart';

/// Root widget: provides the repositories, the API client and the two app-wide blocs
/// ([AuthBloc] and [ProfileCubit]), and returns to the first screen whenever
/// the player signs in or out.
class RevApp extends StatefulWidget {
  const RevApp({super.key, required this.themeCubit, required this.authRepository, required this.userRepository, required this.apiClient});

  final ThemeCubit themeCubit;
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
        RepositoryProvider<SupportApi>(create: (context) => SupportApi(context.read<ApiClient>())),
        RepositoryProvider<LiveApi>(create: (context) => LiveApi(context.read<ApiClient>())),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>.value(value: widget.themeCubit),
          BlocProvider(create: (context) => AuthBloc(context.read<AuthRepository>())),
          BlocProvider(
            create: (context) => ProfileCubit(context.read<UserRepository>(), context.read<WalletApi>())
              ..bind(context.read<AuthBloc>().state.user),
          ),
          BlocProvider(create: (context) => CatalogCubit(context.read<ApiClient>())),
          BlocProvider(create: (context) => LiveCubit(context.read<LiveApi>())),
          BlocProvider(create: (context) => SessionGuard(context.read<ProfileCubit>())),
          BlocProvider(create: (context) => SupportCubit(context.read<UserRepository>())..bind(context.read<AuthBloc>().state.user)),
        ],
        child: MultiBlocListener(
          listeners: [
            // Load the right player's data whenever the signed in player changes.
            BlocListener<AuthBloc, AuthState>(
              listenWhen: (a, b) => a.user.id != b.user.id,
              listener: (context, state) {
                context.read<SessionGuard>().reset();
                context.read<ProfileCubit>().bind(state.user);
                context.read<SupportCubit>().bind(state.user);
                context.read<LiveCubit>().reset();
              },
            ),
            // Close sign up / phone / game pages that are still open on top.
            BlocListener<AuthBloc, AuthState>(
              listenWhen: (a, b) => a.isAuthenticated != b.isAuthenticated,
              listener: (context, state) => _navigatorKey.currentState?.popUntil((route) => route.isFirst),
            ),
          ],
          child: BlocBuilder<ThemeCubit, ThemeState>(
            builder: (context, theme) => MaterialApp(
              navigatorKey: _navigatorKey,
              title: 'REV GAMES',
              debugShowCheckedModeBanner: false,
              theme: buildAppTheme(),
              // Mouse and trackpad can drag lists (Mac, browser), like a finger does.
              scrollBehavior: const MaterialScrollBehavior().copyWith(
                dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus},
              ),
              builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
                value: theme.light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
                // On very wide screens the app stops growing and sits in the middle.
                child: ColoredBox(
                  color: AppColors.bg,
                  child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: Breakpoints.app), child: child ?? const SizedBox.shrink())),
                ),
              ),
              home: const AuthGate(),
            ),
          ),
        ),
      ),
    );
  }
}
