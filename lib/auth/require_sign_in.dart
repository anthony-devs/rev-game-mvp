import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import 'bloc/auth_bloc.dart';
import 'pages/login_page.dart';

/// True when a player is signed in.
bool isSignedIn(BuildContext context) => context.read<AuthBloc>().state.isAuthenticated;

/// Visitors can look around, but anything that needs an account comes here first.
/// Returns true when the player is signed in; otherwise opens the sign in screen and returns false.
bool requireSignIn(BuildContext context) {
  if (isSignedIn(context)) return true;
  openSignIn(context);
  return false;
}

/// The sign in screen on top of whatever the visitor was looking at, with a way back.
/// When sign in finishes the app returns to the home screen by itself.
void openSignIn(BuildContext context) {
  Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const _SignInPage(), fullscreenDialog: true));
}

class _SignInPage extends StatelessWidget {
  const _SignInPage();

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      const LoginPage(),
      SafeArea(
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: PressScale(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.surface, border: Border.all(color: AppColors.line)),
                child: Icon(Icons.close_rounded, color: AppColors.text, size: 22),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
