import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'components/core/app_sound.dart';
import 'auth/data/auth_repository.dart';
import 'core/api/api_client.dart';
import 'core/telemetry/crash_reporter.dart';
import 'firebase_options.dart';
import 'theme/theme_cubit.dart';
import 'user/data/user_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint('Startup failed: $e');
    runApp(const _StartupError(message: 'Please check your connection and open the app again. If this keeps happening, contact support.'));
    return;
  }
  await AppSound.init();
  final theme = await ThemeCubit.load();
  final auth = AuthRepository();
  final api = ApiClient(tokenProvider: auth.idToken, tokenRefresher: () => auth.idToken(force: true));
  CrashReporter.install(api);
  runApp(RevApp(themeCubit: theme, authRepository: auth, userRepository: UserRepository(), apiClient: api));
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0B0B0C), // plain colours: nothing has loaded yet
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not start the app.\n\n$message', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          ),
        ),
      ),
    );
  }
}
