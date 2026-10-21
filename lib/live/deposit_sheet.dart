import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../games/game_support.dart' show pushPage, showToast;
import 'agreement_page.dart';
import 'checkout_page.dart';
import 'live_cubit.dart';

/// Opens the checkout. Makes sure the payment options are loaded and the Live Money Agreement is accepted first.
Future<void> showDepositSheet(BuildContext context) async {
  // The status may be missing (app restarted in live mode). Load it first so the page never hangs.
  final cubit = context.read<LiveCubit>();
  if (!await cubit.ensureStatus()) {
    if (context.mounted) showToast(context, cubit.state.error ?? 'Could not load your payment options. Please try again in a moment.', error: true);
    return;
  }
  if (!context.mounted) return;
  if (cubit.state.status!.needsAgreement && !await showLiveAgreement(context)) return;
  if (!context.mounted) return;
  await cubit.refresh();
  if (!context.mounted) return;
  return pushPage<void>(context, const CheckoutPage());
}
