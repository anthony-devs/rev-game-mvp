import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../core/api/api_client.dart';
import '../games/game_support.dart' show showToast;
import '../user/bloc/profile_cubit.dart';
import 'live_cubit.dart';
import 'method_list.dart';
import 'ng_banks.dart';
import 'live_models.dart';
import 'payment_logo.dart';

Future<void> showWithdrawSheet(BuildContext context) async {
  final cubit = context.read<LiveCubit>();
  if (!await cubit.ensureStatus()) {
    if (context.mounted) showToast(context, cubit.state.error ?? 'Could not load your withdrawal options. Please try again in a moment.', error: true);
    return;
  }
  if (!context.mounted) return;
  await cubit.refresh();
  if (!context.mounted) return;
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
  final _address = TextEditingController();
  final _email = TextEditingController();
  String? _provider; // null = still choosing a method
  String _key = LiveCubit.newKey(); // one key per request: taps and retries can't make a second payout
  bool _busy = false;
  String? _error;
  LivePayment? _sent;

  @override
  void dispose() {
    for (final c in [_amount, _bank, _name, _number, _address, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit(LiveStatus s, double balance, LiveProvider method) async {
    if (_busy) return;
    final amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
    final max = balance < s.maxPayout ? balance : s.maxPayout;
    if (amount == null || amount < s.minPayout || amount > max) {
      setState(() => _error = max < s.minPayout
          ? 'You need at least ${PlayMode.money(s.minPayout, decimals: 0)} to withdraw.'
          : 'Enter an amount from ${PlayMode.money(s.minPayout, decimals: 0)} to ${PlayMode.money(max, decimals: 0)}.');
      return;
    }
    final Map<String, String> destination;
    switch (method.destination) {
      case 'crypto':
        final a = _address.text.trim();
        final ok = method.network == 'TRC20' ? RegExp(r'^T[1-9A-HJ-NP-Za-km-z]{33}$').hasMatch(a) : RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(a);
        if (!ok) {
          setState(() => _error = "That doesn't look like a valid ${method.network} address. Copy it again from your wallet.");
          return;
        }
        destination = {'address': a};
      case 'paypal':
        final e = _email.text.trim();
        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$').hasMatch(e)) {
          setState(() => _error = 'Enter the email address of your PayPal account.');
          return;
        }
        destination = {'email': e};
      default:
        if (_bank.text.trim().length < 2 || _name.text.trim().length < 2 || !RegExp(r'^\d{6,20}$').hasMatch(_number.text.trim())) {
          setState(() => _error = 'Choose your bank and check the account name and number.');
          return;
        }
        destination = {'bankName': _bank.text.trim(), 'accountName': _name.text.trim(), 'accountNumber': _number.text.trim()};
    }
    final cubit = context.read<LiveCubit>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = await cubit.api.payout(provider: method.id, amount: amount, destination: destination, key: _key);
      _key = LiveCubit.newKey();
      if (mounted) setState(() => _sent = p);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.isNetwork ? '${e.message} Tap again; you will not be paid twice.' : e.message);
    } finally {
      cubit.refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LiveCubit>().state.status;
    final balance = context.select((ProfileCubit c) => c.state.wallet.balance);
    if (s == null) return const Padding(padding: EdgeInsets.all(30), child: Center(child: AppLoader()));

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
    final method = providers.where((p) => p.id == _provider).firstOrNull;
    if (method == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Choose where to send your money', style: AppText.body(14, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text('Withdraw to an account or wallet in your own name.', style: AppText.body(12, color: AppColors.textDim)),
          const SizedBox(height: 12),
          if (providers.isEmpty) Text('Withdrawals are not available right now.', style: AppText.body(14, color: AppColors.textMuted)) else MethodList(providers: providers, onPick: (p) => setState(() => _provider = p.id)),
        ],
      );
    }
    final amount = double.tryParse(_amount.text.replaceAll(',', '').trim());
    final quote = amount == null ? '' : method.payText(amount);
    return PopScope(
      canPop: !_busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            IconSquareButton(icon: Icons.chevron_left_rounded, semanticLabel: 'Back', size: 40, iconSize: 22, onPressed: _busy ? null : () => setState(() {
                  _provider = null;
                  _error = null;
                })),
            const SizedBox(width: 12),
            PaymentLogo(method.id, width: 52, height: 36),
            const SizedBox(width: 10),
            Expanded(child: Text(method.label, style: AppText.body(16, weight: FontWeight.w800))),
          ]),
          const SizedBox(height: 14),
          Text('AVAILABLE ${PlayMode.money(balance)}', style: AppText.label()),
          const SizedBox(height: 12),
          AppTextField(
            label: 'Amount (${s.currency})',
            hint: 'Min ${s.minPayout.toStringAsFixed(0)}',
            controller: _amount,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            onChanged: (_) => setState(() => _error = null),
          ),
          if (quote.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('You receive about $quote  (1 ${method.payCurrency} = ${PlayMode.money(method.rate, decimals: 0)})', style: AppText.body(12, color: AppColors.textMuted)),
          ],
          const SizedBox(height: 14),
          if (method.destination == 'crypto') ...[
            AppTextField(label: '${method.network} wallet address', controller: _address, enabled: !_busy, textInputAction: TextInputAction.done),
            const SizedBox(height: 8),
            Text('Double-check the address and network. A payment sent to a wrong address cannot be recovered.', style: AppText.body(12, color: AppColors.loss, height: 1.4)),
          ] else if (method.destination == 'paypal') ...[
            AppTextField(label: 'PayPal email', controller: _email, enabled: !_busy, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.done),
          ] else ...[
            PressScale(
              onTap: _busy ? null : _pickBank,
              scale: .99,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
                child: Row(children: [
                  Expanded(child: Text(_bank.text.isEmpty ? 'Choose your bank' : _bank.text, style: AppText.body(15, color: _bank.text.isEmpty ? AppColors.textDim : AppColors.text))),
                  Icon(Icons.expand_more_rounded, color: AppColors.textDim),
                ]),
              ),
            ),
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
          ],
          const SizedBox(height: 12),
          if (method.eta.isNotEmpty || method.fee.isNotEmpty)
            Text([if (method.eta.isNotEmpty) 'Time: ${method.eta}', if (method.fee.isNotEmpty) 'Fee: ${method.fee}'].join('   '), style: AppText.body(12, color: AppColors.textDim)),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: AppText.body(13, color: AppColors.loss, height: 1.4)),
          ],
          const SizedBox(height: 16),
          AppButton(label: 'Request withdrawal', variant: AppButtonVariant.gold, loading: _busy, onPressed: _busy ? null : () => _submit(s, balance, method)),
          const SizedBox(height: 8),
          Center(child: Text('Payouts are reviewed by our team before they are sent.', style: AppText.body(12, color: AppColors.textDim))),
        ],
      ),
    );
  }

  Future<void> _pickBank() async {
    final picked = await showAppBottomSheet<String>(
      context,
      title: 'Choose your bank',
      child: Column(
        children: [
          for (final b in kNigerianBanks)
            Builder(
              builder: (ctx) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(b, style: AppText.body(15)),
                trailing: _bank.text == b ? Icon(Icons.check_rounded, color: AppColors.green) : null,
                onTap: () => Navigator.of(ctx).pop(b),
              ),
            ),
        ],
      ),
    );
    if (picked != null && mounted) setState(() => _bank.text = picked);
  }
}
