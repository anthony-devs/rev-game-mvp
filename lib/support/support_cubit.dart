import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../model/model.dart';
import '../user/data/user_repository.dart';
import 'support_models.dart';

class SupportState extends Equatable {
  const SupportState({this.tickets = const [], this.ready = false});

  final List<Ticket> tickets;
  final bool ready;

  /// Tickets with a reply the player hasn't read. Drives the badge.
  int get unread => tickets.where((t) => t.unread).length;
  int get openCount => tickets.where((t) => !t.isClosed).length;

  Ticket? byId(String id) {
    for (final t in tickets) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  List<Object?> get props => [tickets, ready];
}

/// The signed in player's tickets, live. One instance for the whole app.
class SupportCubit extends Cubit<SupportState> {
  SupportCubit(this._repo) : super(const SupportState());

  final UserRepository _repo;
  StreamSubscription<List<Ticket>>? _sub;

  void bind(AppUser user) {
    _sub?.cancel();
    _sub = null;
    if (user.isEmpty) {
      emit(const SupportState());
      return;
    }
    _sub = _repo.watchTickets(user.id).listen((t) => emit(SupportState(tickets: t, ready: true)), onError: (_) {});
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
