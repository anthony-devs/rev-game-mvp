import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'auth/data/auth_repository.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    runApp(_StartupError(message: '$e'));
    return;
  }
  runApp(RevApp(authRepository: AuthRepository()));
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0B0B0C),
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
