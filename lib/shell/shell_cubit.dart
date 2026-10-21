import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Tab order of the bottom bar.
class ShellTab {
  ShellTab._();
  static const int browse = 0;
  static const int casino = 1;
  static const int slots = 2;
  static const int events = 3;
  static const int settings = 4;
}

class ShellState extends Equatable {
  const ShellState({this.tab = ShellTab.casino, this.filter, this.favouritesOnly = false});

  final int tab;

  /// Lobby chip: a group id (originals, crash, ...); `null` = All.
  final String? filter;
  final bool favouritesOnly;

  @override
  List<Object?> get props => [tab, filter, favouritesOnly];
}

/// Which tab is open and which chip the lobby shows. Lets Browse jump to
/// "Instant games" in the Casino tab.
class ShellCubit extends Cubit<ShellState> {
  ShellCubit() : super(const ShellState());

  void go(int tab, {String? filter, bool favouritesOnly = false}) =>
      emit(ShellState(tab: tab, filter: filter, favouritesOnly: favouritesOnly));

  void setFilter(String? filter, {bool favouritesOnly = false}) =>
      emit(ShellState(tab: state.tab, filter: filter, favouritesOnly: favouritesOnly));
}
