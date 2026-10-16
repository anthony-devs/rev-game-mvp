import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/auth_failure.dart';
import '../data/auth_repository.dart';

enum PhoneStep { enterNumber, enterCode }

class PhoneAuthState extends Equatable {
  const PhoneAuthState({
    this.step = PhoneStep.enterNumber,
    this.busy = false,
    this.error,
    this.phone = '',
    this.secondsLeft = 0,
  });

  final PhoneStep step;
  final bool busy;
  final String? error;

  /// The full number the code was sent to, e.g. +2348012345678.
  final String phone;

  /// Seconds until "Resend" works again.
  final int secondsLeft;

  PhoneAuthState copyWith({PhoneStep? step, bool? busy, String? error, String? phone, int? secondsLeft, bool clearError = false}) {
    return PhoneAuthState(
      step: step ?? this.step,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
      phone: phone ?? this.phone,
      secondsLeft: secondsLeft ?? this.secondsLeft,
    );
  }

  @override
  List<Object?> get props => [step, busy, error, phone, secondsLeft];
}

/// Two steps: send the SMS code, then check it.
class PhoneAuthCubit extends Cubit<PhoneAuthState> {
  PhoneAuthCubit(this._repo) : super(const PhoneAuthState());

  static const int resendSeconds = 30;

  final AuthRepository _repo;
  String? _verificationId;
  int? _resendToken;
  Timer? _timer;

  void clearError() {
    if (state.error != null) emit(state.copyWith(clearError: true));
  }

  Future<void> sendCode(String phone) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, phone: phone, clearError: true));
    try {
      final result = await _repo.requestPhoneCode(phone, resendToken: _resendToken);
      if (isClosed) return;
      if (result.signedIn) {
        emit(state.copyWith(busy: false));
        return;
      }
      _verificationId = result.verificationId;
      _resendToken = result.resendToken;
      emit(state.copyWith(step: PhoneStep.enterCode, busy: false));
      _startCountdown();
    } on AuthFailure catch (e) {
      if (!isClosed) emit(state.copyWith(busy: false, error: e.message));
    } catch (_) {
      if (!isClosed) emit(state.copyWith(busy: false, error: 'Could not send the code. Try again.'));
    }
  }

  Future<void> resend() {
    if (state.secondsLeft > 0) return Future.value();
    return sendCode(state.phone);
  }

  Future<void> verify(String code) async {
    final id = _verificationId;
    if (state.busy || id == null) return;
    emit(state.copyWith(busy: true, clearError: true));
    try {
      await _repo.verifySmsCode(verificationId: id, code: code);
      if (!isClosed) emit(state.copyWith(busy: false));
    } on AuthFailure catch (e) {
      if (!isClosed) emit(state.copyWith(busy: false, error: e.message));
    } catch (_) {
      if (!isClosed) emit(state.copyWith(busy: false, error: 'Could not verify the code. Try again.'));
    }
  }

  void changeNumber() {
    _timer?.cancel();
    _verificationId = null;
    _resendToken = null;
    emit(const PhoneAuthState());
  }

  void _startCountdown() {
    _timer?.cancel();
    emit(state.copyWith(secondsLeft: resendSeconds));
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = state.secondsLeft - 1;
      if (left <= 0) t.cancel();
      emit(state.copyWith(secondsLeft: left < 0 ? 0 : left));
    });
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
