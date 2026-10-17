import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../core/api/api_client.dart';
import '../user/bloc/profile_cubit.dart';
import 'live_cubit.dart';
import 'live_models.dart';
import 'payment_logo.dart';

Future<void> showWithdrawSheet(BuildContext context) {
  return showAppBottomSheet<void>(context, title: 'Withdraw', child: const _WithdrawBody());
}

class _WithdrawBody extends StatefulWidget {
  const _WithdrawBody();

  @override
  State<_WithdrawBody> createState() => _WithdrawBodyState();
}

class _WithdrawBodyState extends State<_WithdrawBody> {
  final _amount = TextEditingController();
  final _bank = TextEditingController();
  final _name = TextEditingController();
  final _number = TextEditingController();
  String? _provider;
  String _key = LiveCubit.newKey(); // one key per request: taps and retries can't make a second payout
  bool _busy = false;
  String? _error;
  LivePayment? _sent;

  @override
  void dispose() {
    for (final c in [_amount, _bank, _name, _number]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit(LiveStatus s, double balance, List<LiveProvider> providers) async {
    if (_busy) return;
    final amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
    final max = balance < s.maxPayout ? balance : s.maxPayout;
    if (amount == null || amount < s.minPayout || amount > max) {
      setState(() => _error = max < s.minPayout
          ? 'You need at least ${PlayMode.money(s.minPayout, decimals: 0)} to withdraw.'
          : 'Enter an amount from ${PlayMode.money(s.minPayout, decimals: 0)} to ${PlayMode.money(max, decimals: 0)}.');
      return;
    }
    if (_bank.text.trim().length < 2 || _name.text.trim().length < 2 || !RegExp(r'^\d{6,20}$').hasMatch(_number.text.trim())) {
      setState(() => _error = 'Check the bank name, account name and account number.');
      return;
    }
    final cubit = context.read<LiveCubit>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await cubit.api.payout(
        provider: _provider ?? providers.first.id,
        amount: amount,
        bankName: _bank.text.trim(),
        accountName: _name.text.trim(),
        accountNumber: _number.text.trim(),
        key: _key,
      );
      _key = LiveCubit.newKey();
      if (mounted) setState(() => _sent = p);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.isNetwork ? 'No connection. Tap again; you will not be paid twice.' : e.message);
    } finally {
      cubit.refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LiveCubit>().state.status;
    final balance = context.select((ProfileCubit c) => c.state.wallet.balance);
    if (s == null) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()));

    if (_sent != null) {
      return Column(children: [
        Icon(Icons.hourglass_top_rounded, size: 56, color: AppColors.gold),
        const SizedBox(height: 12),
        Text('Withdrawal requested', style: AppText.body(18, weight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          '${PlayMode.money(_sent!.amount)} is on hold. Our team checks every payout before it is sent. Reference ${_sent!.reference}.',
          textAlign: TextAlign.center,
          style: AppText.body(14, color: AppColors.textMuted, height: 1.5),
        ),
        const SizedBox(height: 20),
        AppButton(label: 'Done', variant: AppButtonVariant.gold, onPressed: () => Navigator.of(context).pop()),
      ]);
    }

    final providers = [for (final p in s.providers) if (p.payout) p];
    final chosen = _provider ?? (providers.isEmpty ? null : providers.first.id);
    return PopScope(
      canPop: !_busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('AVAILABLE ${PlayMode.money(balance)}', style: AppText.label()),
          const SizedBox(height: 12),
          AppTextField(
            label: 'Amount (${s.currency})',
            hint: 'Min ${s.minPayout.toStringAsFixed(0)}',
            controller: _amount,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          ),
          const SizedBox(height: 14),
          Text('SEND VIA', style: AppText.label()),
          const SizedBox(height: 8),
          ProviderPicker(providers: providers, chosen: chosen, onChanged: _busy ? null : (id) => setState(() => _provider = id)),
          const SizedBox(height: 14),
          AppTextField(label: 'Bank name', controller: _bank, enabled: !_busy, textInputAction: TextInputAction.next),
          const SizedBox(height: 10),
          AppTextField(label: 'Account name', controller: _name, enabled: !_busy, textInputAction: TextInputAction.next),
          const SizedBox(height: 10),
          AppTextField(
            label: 'Account number',
            controller: _number,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: AppText.body(13, color: AppColors.loss, height: 1.4)),
          ],
          const SizedBox(height: 16),
          AppButton(label: 'Request withdrawal', variant: AppButtonVariant.gold, loading: _busy, onPressed: _busy || providers.isEmpty ? null : () => _submit(s, balance, providers)),
          const SizedBox(height: 8),
          Center(child: Text('Payouts are reviewed by our team before they are sent.', style: AppText.body(12, color: AppColors.textDim))),
        ],
      ),
    );
  }
}
