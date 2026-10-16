import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/auth_failure.dart';
import '../data/auth_repository.dart';

/// Which button is spinning.
enum AuthMethod { email, google, guest, reset }

class AuthFormState extends Equatable {
  const AuthFormState({this.busy, this.error, this.info});

  /// `null` when idle.
  final AuthMethod? busy;
  final String? error;
  final String? info;

  bool get isBusy => busy != null;

  @override
  List<Object?> get props => [busy, error, info];
}

/// Email sign in, sign up, Google, guest and password reset.
/// On success the [AuthBloc] sees the new user, so nothing is emitted here.
class AuthFormCubit extends Cubit<AuthFormState> {
  AuthFormCubit(this._repo) : super(const AuthFormState());

  final AuthRepository _repo;

  void clearMessages() {
    if (state.error != null || state.info != null) emit(const AuthFormState());
  }

  Future<void> signIn({required String email, required String password}) =>
      _run(AuthMethod.email, () => _repo.signInWithEmail(email: email, password: password));

  Future<void> signUp({required String name, required String email, required String password}) =>
      _run(AuthMethod.email, () => _repo.signUpWithEmail(name: name, email: email, password: password));

  Future<void> google() => _run(AuthMethod.google, _repo.signInWithGoogle);

  Future<void> guest() => _run(AuthMethod.guest, _repo.signInAsGuest);

  Future<void> sendReset(String email) => _run(
        AuthMethod.reset,
        () => _repo.sendPasswordReset(email),
        info: 'Reset link sent. Check your inbox (and spam).',
      );

  Future<void> _run(AuthMethod method, Future<void> Function() action, {String? info}) async {
    if (state.isBusy) return;
    emit(AuthFormState(busy: method));
    try {
      await action();
      if (!isClosed) emit(AuthFormState(info: info));
    } on AuthFailure catch (e) {
      if (!isClosed) emit(AuthFormState(error: e.cancelled ? null : e.message));
    } catch (_) {
      if (!isClosed) emit(const AuthFormState(error: 'Something went wrong. Please try again.'));
    }
  }
}
