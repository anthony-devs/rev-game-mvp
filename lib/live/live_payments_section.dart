import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../core/api/api_client.dart';
import '../games/game_support.dart';
import 'deposit_sheet.dart';
import 'live_cubit.dart';
import 'live_models.dart';
import 'withdraw_sheet.dart';

/// Deposit / withdraw buttons for the wallet card.
List<Widget> liveWalletActions(BuildContext context) => [
      AppButton(label: 'Add money', variant: AppButtonVariant.gold, height: 50, fontSize: 15, onPressed: () => showDepositSheet(context)),
      AppButton(label: 'Withdraw', variant: AppButtonVariant.outline, height: 50, fontSize: 15, onPressed: () => showWithdrawSheet(context)),
    ];

/// Deposits and withdrawals, newest first. A deposit that never finished can be checked here.
class LivePaymentsSection extends StatefulWidget {
  const LivePaymentsSection({super.key});

  @override
  State<LivePaymentsSection> createState() => _LivePaymentsSectionState();
}

class _LivePaymentsSectionState extends State<LivePaymentsSection> {
  final Set<String> _checking = {};

  @override
  void initState() {
    super.initState();
    context.read<LiveCubit>().refresh();
  }

  Future<void> _check(LivePayment p) async {
    if (!_checking.add(p.id)) return;
    setState(() {});
    final cubit = context.read<LiveCubit>();
    try {
      final r = await cubit.api.verify(p.id);
      if (mounted && r.status == 'succeeded') showToast(context, '${PlayMode.money(r.amount)} added.');
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    }
    await cubit.refresh();
    _checking.remove(p.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final payments = context.watch<LiveCubit>().state.payments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: 'Deposits & withdrawals', padding: EdgeInsets.zero),
        const SizedBox(height: 10),
        if (payments.isEmpty)
          InfoCard(title: 'No payments yet', message: 'Add money to start playing with real funds.')
        else
          for (final p in payments.take(15)) _row(p),
      ],
    );
  }

  Widget _row(LivePayment p) {
    final color = switch (p.status) {
      'succeeded' || 'paid' => AppColors.green,
      'failed' || 'flagged' => AppColors.loss,
      'rejected' => AppColors.textDim,
      _ => AppColors.gold,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      child: Row(
        children: [
          Icon(p.isDeposit ? Icons.south_west_rounded : Icons.north_east_rounded, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.isDeposit ? 'Deposit' : 'Withdrawal${p.accountLast4.isEmpty ? '' : ' to ••${p.accountLast4}'}', style: AppText.body(14, weight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                '${p.statusLabel}${p.reference.isEmpty ? '' : ' · ref ${p.reference}'}${p.createdAt == null ? '' : ' · ${_when(p.createdAt!)}'}',
                style: AppText.body(12, color: AppColors.textDim),
              ),
              if (p.note.isNotEmpty && (p.status == 'rejected' || p.status == 'failed'))
                Padding(padding: const EdgeInsets.only(top: 2), child: Text(p.note, style: AppText.body(12, color: AppColors.textMuted))),
            ]),
          ),
          const SizedBox(width: 8),
          if (p.isDeposit && p.open)
            SizedBox(
              height: 34,
              child: TextButton(onPressed: _checking.contains(p.id) ? null : () => _check(p), child: Text(_checking.contains(p.id) ? '...' : 'Check', style: AppText.body(13, weight: FontWeight.w700, color: AppColors.gold))),
            )
          else
            Text('${p.isDeposit ? '+' : '-'}${PlayMode.money(p.amount, decimals: 0)}', style: AppText.number(15, color: color)),
        ],
      ),
    );
  }

  String _when(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.day}/${l.month} ${two(l.hour)}:${two(l.minute)}';
  }
}
