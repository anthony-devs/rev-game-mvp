import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../components/components.dart';
import '../bloc/auth_form_cubit.dart';
import '../data/auth_repository.dart';
import '../data/auth_validators.dart';
import '../widgets/auth_layout.dart';
import '../widgets/auth_widgets.dart';

/// Create an account with name, email and password.
class SignUpPage extends StatelessWidget {
  const SignUpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AuthFormCubit(context.read<AuthRepository>()),
      child: const _SignUpView(),
    );
  }
}

class _SignUpView extends StatefulWidget {
  const _SignUpView();

  @override
  State<_SignUpView> createState() => _SignUpViewState();
}

class _SignUpViewState extends State<_SignUpView> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  String? _nameError;
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final n = AuthValidators.name(_name.text);
    final e = AuthValidators.email(_email.text);
    final p = AuthValidators.password(_password.text);
    setState(() {
      _nameError = n;
      _emailError = e;
      _passwordError = p;
    });
    if (n != null || e != null || p != null) return;
    FocusScope.of(context).unfocus();
    context.read<AuthFormCubit>().signUp(name: _name.text, email: _email.text, password: _password.text);
  }

  void _edited() {
    context.read<AuthFormCubit>().clearMessages();
    if (_nameError != null || _emailError != null || _passwordError != null) {
      setState(() {
        _nameError = null;
        _emailError = null;
        _passwordError = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthFormCubit, AuthFormState>(
      builder: (context, state) {
        return AuthLayout(
          title: 'Create account',
          subtitle: 'Create your account to start playing.',
          children: [
            AuthBanner(error: state.error, info: state.info),
            AutofillGroup(
              child: Column(
                children: [
                  AppTextField(
                    label: 'Name',
                    hint: 'What should we call you?',
                    controller: _name,
                    errorText: _nameError,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.nickname],
                    onChanged: (_) => _edited(),
                  ),
                  const SizedBox(height: 16),
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
                    hint: 'At least 6 characters',
                    controller: _password,
                    errorText: _passwordError,
                    obscure: _obscure,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    onChanged: (_) => _edited(),
                    onSubmitted: (_) => _submit(),
                    suffix: PasswordToggle(obscured: _obscure, onTap: () => setState(() => _obscure = !_obscure)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            AppButton(
              label: 'Create account',
              loading: state.busy == AuthMethod.email,
              onPressed: state.isBusy ? null : _submit,
            ),
            const SizedBox(height: 12),
            const AuthLegalNote(action: 'creating an account'),
            const SizedBox(height: 8),
            AuthLink(
              prefix: 'Already have an account?',
              action: 'Sign in',
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ],
        );
      },
    );
  }
}
