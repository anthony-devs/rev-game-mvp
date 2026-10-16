import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../components/components.dart';
import '../bloc/auth_form_cubit.dart';
import '../data/auth_repository.dart';
import '../data/auth_validators.dart';
import '../widgets/auth_layout.dart';
import '../widgets/auth_widgets.dart';

/// Sends a password reset email.
class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AuthFormCubit(context.read<AuthRepository>()),
      child: _ForgotView(initialEmail: initialEmail),
    );
  }
}

class _ForgotView extends StatefulWidget {
  const _ForgotView({required this.initialEmail});

  final String initialEmail;

  @override
  State<_ForgotView> createState() => _ForgotViewState();
}

class _ForgotViewState extends State<_ForgotView> {
  late final TextEditingController _email = TextEditingController(text: widget.initialEmail);
  String? _emailError;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    final e = AuthValidators.email(_email.text);
    setState(() => _emailError = e);
    if (e != null) return;
    FocusScope.of(context).unfocus();
    context.read<AuthFormCubit>().sendReset(_email.text);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthFormCubit, AuthFormState>(
      builder: (context, state) {
        return AuthLayout(
          title: 'Reset password',
          subtitle: 'Enter your email and we will send you a link to choose a new password.',
          children: [
            AuthBanner(error: state.error, info: state.info),
            AppTextField(
              label: 'Email',
              hint: 'you@example.com',
              controller: _email,
              errorText: _emailError,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              onChanged: (_) {
                context.read<AuthFormCubit>().clearMessages();
                if (_emailError != null) setState(() => _emailError = null);
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            AppButton(
              label: 'Send reset link',
              loading: state.busy == AuthMethod.reset,
              onPressed: state.isBusy ? null : _submit,
            ),
            const SizedBox(height: 16),
            AuthLink(action: 'Back to sign in', onTap: () => Navigator.of(context).maybePop()),
          ],
        );
      },
    );
  }
}
