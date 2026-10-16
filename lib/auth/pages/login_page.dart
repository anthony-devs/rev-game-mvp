import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../components/components.dart';
import '../../pages/help_page.dart';
import '../bloc/auth_form_cubit.dart';
import '../data/auth_repository.dart';
import '../data/auth_validators.dart';
import '../widgets/auth_layout.dart';
import '../widgets/auth_widgets.dart';
import 'forgot_password_page.dart';
import 'phone_page.dart';
import 'sign_up_page.dart';

/// First screen for signed-out players. Email, Google, phone or guest.
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AuthFormCubit(context.read<AuthRepository>()),
      child: const _LoginView(),
    );
  }
}

class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final emailError = AuthValidators.email(_email.text);
    final passwordError = _password.text.isEmpty ? 'Enter your password' : null;
    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
    });
    if (emailError != null || passwordError != null) return;
    FocusScope.of(context).unfocus();
    context.read<AuthFormCubit>().signIn(email: _email.text, password: _password.text);
  }

  void _edited() {
    context.read<AuthFormCubit>().clearMessages();
    if (_emailError != null || _passwordError != null) {
      setState(() {
        _emailError = null;
        _passwordError = null;
      });
    }
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthFormCubit, AuthFormState>(
      builder: (context, state) {
        final cubit = context.read<AuthFormCubit>();
        return AuthLayout(
          title: 'Welcome back',
          subtitle: 'Sign in to keep your credits, level and history.',
          showBack: false,
          children: [
            AuthBanner(error: state.error, info: state.info),
            AutofillGroup(
              child: Column(
                children: [
                  AppTextField(
                    label: 'Email',
                    hint: 'you@example.com',
                    controller: _email,
                    errorText: _emailError,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    onChanged: (_) => _edited(),
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Password',
                    hint: 'Your password',
                    controller: _password,
                    errorText: _passwordError,
                    obscure: _obscure,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onChanged: (_) => _edited(),
                    onSubmitted: (_) => _submit(),
                    suffix: PasswordToggle(obscured: _obscure, onTap: () => setState(() => _obscure = !_obscure)),
                  ),
                ],
              ),
            ),
            AuthLink(
              action: 'Forgot password?',
              center: false,
              onTap: () => _push(ForgotPasswordPage(initialEmail: _email.text.trim())),
            ),
            const SizedBox(height: 8),
            AppButton(
              label: 'Sign in',
              loading: state.busy == AuthMethod.email,
              onPressed: state.isBusy ? null : _submit,
            ),
            const AuthDivider(label: 'or continue with'),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Google',
                    icon: Icons.g_mobiledata_rounded,
                    variant: AppButtonVariant.outline,
                    height: 52,
                    fontSize: 14,
                    loading: state.busy == AuthMethod.google,
                    onPressed: state.isBusy ? null : cubit.google,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: 'Phone',
                    icon: Icons.phone_iphone_rounded,
                    variant: AppButtonVariant.outline,
                    height: 52,
                    fontSize: 14,
                    onPressed: state.isBusy ? null : () => _push(const PhonePage()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Play as guest',
              variant: AppButtonVariant.ghost,
              height: 52,
              fontSize: 14,
              loading: state.busy == AuthMethod.guest,
              onPressed: state.isBusy ? null : cubit.guest,
            ),
            const SizedBox(height: 8),
            Text(
              'Guests start with 10,000 demo credits. Progress is saved to this guest account.',
              textAlign: TextAlign.center,
              style: AppText.body(12, color: AppColors.textDim),
            ),
            const SizedBox(height: 20),
            AuthLink(
              prefix: 'New here?',
              action: 'Create account',
              onTap: state.isBusy ? null : () => _push(const SignUpPage()),
            ),
            AuthLink(
              prefix: 'Need help?',
              action: 'Help Centre',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HelpPage())),
            ),
          ],
        );
      },
    );
  }
}
