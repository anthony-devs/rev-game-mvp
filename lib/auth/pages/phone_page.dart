import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../components/components.dart';
import '../bloc/phone_auth_cubit.dart';
import '../data/auth_repository.dart';
import '../data/auth_validators.dart';
import '../widgets/auth_layout.dart';
import '../widgets/auth_widgets.dart';

/// Sign in with a phone number: enter the number, then the SMS code.
class PhonePage extends StatelessWidget {
  const PhonePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => PhoneAuthCubit(context.read<AuthRepository>()),
      child: const _PhoneView(),
    );
  }
}

class _PhoneView extends StatefulWidget {
  const _PhoneView();

  @override
  State<_PhoneView> createState() => _PhoneViewState();
}

class _PhoneViewState extends State<_PhoneView> {
  final _code = TextEditingController(text: '+234');
  final _number = TextEditingController();
  final _otp = TextEditingController();
  String? _codeError;
  String? _numberError;

  @override
  void dispose() {
    _code.dispose();
    _number.dispose();
    _otp.dispose();
    super.dispose();
  }

  void _send() {
    final c = AuthValidators.countryCode(_code.text);
    final n = AuthValidators.phoneNumber(_number.text);
    setState(() {
      _codeError = c;
      _numberError = n;
    });
    if (c != null || n != null) return;
    FocusScope.of(context).unfocus();
    context.read<PhoneAuthCubit>().sendCode(AuthValidators.e164(_code.text, _number.text));
  }

  void _verify() {
    if (_otp.text.length != 6) return;
    FocusScope.of(context).unfocus();
    context.read<PhoneAuthCubit>().verify(_otp.text);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PhoneAuthCubit, PhoneAuthState>(
      buildWhen: (a, b) => a.step != b.step || a.busy != b.busy || a.error != b.error || a.phone != b.phone,
      builder: (context, state) {
        final cubit = context.read<PhoneAuthCubit>();
        if (state.step == PhoneStep.enterNumber) {
          return AuthLayout(
            title: 'Your phone',
            subtitle: 'We will text you a 6 digit code to confirm it is you.',
            children: [
              AuthBanner(error: state.error),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 104,
                    child: AppTextField(
                      label: 'Code',
                      controller: _code,
                      errorText: _codeError,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[+\d]')), LengthLimitingTextInputFormatter(5)],
                      onChanged: (_) => _clearErrors(cubit),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppTextField(
                      label: 'Phone number',
                      hint: '801 234 5678',
                      controller: _number,
                      errorText: _numberError,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.telephoneNumberNational],
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\s-]')), LengthLimitingTextInputFormatter(16)],
                      onChanged: (_) => _clearErrors(cubit),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              AppButton(label: 'Send code', loading: state.busy, onPressed: state.busy ? null : _send),
            ],
          );
        }

        return AuthLayout(
          title: 'Enter the code',
          subtitle: 'Sent to ${state.phone}',
          children: [
            AuthBanner(error: state.error),
            AppTextField(
              label: '6 digit code',
              hint: '------',
              controller: _otp,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              onChanged: (v) {
                cubit.clearError();
                if (v.length == 6) _verify();
              },
              onSubmitted: (_) => _verify(),
            ),
            const SizedBox(height: 24),
            AppButton(label: 'Verify', loading: state.busy, onPressed: state.busy ? null : _verify),
            const SizedBox(height: 12),
            BlocSelector<PhoneAuthCubit, PhoneAuthState, int>(
              selector: (s) => s.secondsLeft,
              builder: (context, left) {
                return AuthLink(
                  prefix: left > 0 ? 'Did not get it?' : null,
                  action: left > 0 ? 'Resend in ${left}s' : 'Resend code',
                  onTap: left > 0 || state.busy ? null : cubit.resend,
                );
              },
            ),
            AuthLink(
              action: 'Use a different number',
              onTap: () {
                _otp.clear();
                cubit.changeNumber();
              },
            ),
          ],
        );
      },
    );
  }

  void _clearErrors(PhoneAuthCubit cubit) {
    cubit.clearError();
    if (_codeError != null || _numberError != null) {
      setState(() {
        _codeError = null;
        _numberError = null;
      });
    }
  }
}
