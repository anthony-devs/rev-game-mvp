import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../model/model.dart';
import '../../push/push_registration.dart';
import '../data/auth_repository.dart';

enum AuthStatus { authenticated, unauthenticated }

class AuthState extends Equatable {
  const AuthState._(this.status, this.user);

  const AuthState.authenticated(AppUser user) : this._(AuthStatus.authenticated, user);
  const AuthState.unauthenticated() : this._(AuthStatus.unauthenticated, AppUser.empty);

  final AuthStatus status;
  final AppUser user;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  @override
  List<Object?> get props => [status, user];
}

sealed class AuthEvent {
  const AuthEvent();
}

class _UserChanged extends AuthEvent {
  const _UserChanged(this.user);
  final AppUser user;
}

class AuthSignOutRequested extends AuthEvent {
  const AuthSignOutRequested();
}

/// Who is signed in. The whole app listens to this one bloc.
///
/// ```dart
/// context.read<AuthBloc>().add(const AuthSignOutRequested());
/// final name = context.select((AuthBloc b) => b.state.user.displayName);
/// ```
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc(this._repo) : super(_initial(_repo.currentUser)) {
    on<_UserChanged>(_onUserChanged);
    on<AuthSignOutRequested>((event, emit) async {
      // Stopping push messages needs the network. Never let a slow server hold up signing out.
      try {
        await PushRegistration.stop().timeout(const Duration(milliseconds: 1500));
      } catch (_) {}
      await _repo.signOut();
    });
    _sub = _repo.user.listen((u) => add(_UserChanged(u)));
  }

  final AuthRepository _repo;
  late final StreamSubscription<AppUser> _sub;

  static AuthState _initial(AppUser u) =>
      u.isEmpty ? const AuthState.unauthenticated() : AuthState.authenticated(u);

  void _onUserChanged(_UserChanged event, Emitter<AuthState> emit) {
    if (event.user.isEmpty) {
      emit(const AuthState.unauthenticated());
    } else {
      emit(AuthState.authenticated(event.user));
    }
  }

  @override
  Future<void> close() {
    _sub.cancel();
    return super.close();
  }
}
