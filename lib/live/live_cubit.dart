import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/core/play_mode.dart';
import '../core/api/api_client.dart';
import 'live_api.dart';
import 'live_models.dart';

class LiveState extends Equatable {
  const LiveState({this.status, this.payments = const [], this.loading = false, this.error});
  final LiveStatus? status;
  final List<LivePayment> payments;
  final bool loading;
  final String? error;

  @override
  List<Object?> get props => [status, payments, loading, error];
}

/// Live-money info that isn't the balance (the balance comes from the live wallet document).
class LiveCubit extends Cubit<LiveState> {
  LiveCubit(this.api) : super(const LiveState());
  final LiveApi api;

  static final _rng = Random.secure();

  /// A fresh idempotency key. One per attempt: kept until the attempt has an answer.
  static String newKey() => List.generate(24, (_) => _rng.nextInt(16).toRadixString(16)).join();

  void reset() => emit(const LiveState());

  /// Loads status and history. Returns an error message, or `null` when live play can start.
  Future<String?> enter() async {
    emit(LiveState(status: state.status, payments: state.payments, loading: true));
    try {
      final r = await Future.wait<Object>([api.status(), api.payments()]);
      final status = r[0] as LiveStatus;
      PlayMode.setCurrency(status.currency);
      emit(LiveState(status: status, payments: r[1] as List<LivePayment>));
      return status.enabled ? null : (status.message.isEmpty ? 'Live play is not available right now.' : status.message);
    } on ApiException catch (e) {
      emit(LiveState(status: state.status, payments: state.payments, error: e.message));
      return e.isNetwork ? "Can't reach the game server." : e.message;
    } catch (_) {
      emit(LiveState(status: state.status, payments: state.payments, error: 'Something went wrong.'));
      return 'Something went wrong. Please try again.';
    }
  }

  Future<void> refresh() async {
    try {
      final r = await Future.wait<Object>([api.status(), api.payments()]);
      emit(LiveState(status: r[0] as LiveStatus, payments: r[1] as List<LivePayment>));
    } catch (_) {}
  }
}
