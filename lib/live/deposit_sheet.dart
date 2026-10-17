import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../core/api/api_client.dart';
import 'live_cubit.dart';
import 'live_models.dart';
import 'mock_gateway.dart';
import 'payment_logo.dart';

Future<void> showDepositSheet(BuildContext context) {
  return showAppBottomSheet<void>(context, title: 'Add money', child: const _DepositBody());
}

bool _availableHere(String id) {
  if (id == 'apple_pay') return defaultTargetPlatform == TargetPlatform.iOS;
  if (id == 'google_pay') return defaultTargetPlatform == TargetPlatform.android;
  return true;
}

class _DepositBody extends StatefulWidget {
  const _DepositBody();

  @override
  State<_DepositBody> createState() => _DepositBodyState();
}

class _DepositBodyState extends State<_DepositBody> {
  final _amount = TextEditingController(text: '5000');
  String? _provider;

  /// One key per attempt. Taps and retries of the same attempt reuse it, so the server
  /// can only ever create one payment for it. It changes only once the attempt has an answer.
  String _key = LiveCubit.newKey();
  bool _busy = false;
  String? _error;
  String _phase = '';
  String? _done;
  LivePayment? _unfinished;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  double? get _value => double.tryParse(_amount.text.replaceAll(',', '').trim());

  Future<LivePayment> _settle(LiveCubit cubit, String id) async {
    LivePayment p = await cubit.api.verify(id);
    for (var i = 0; i < 5 && (p.status == 'pending' || p.status == 'created'); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      p = await cubit.api.verify(id);
    }
    return p;
  }

  Future<void> _pay(LiveStatus s, List<LiveProvider> providers) async {
    if (_busy) return; // second tap while the first is still running
    final amount = _value;
    final provider = _provider ?? providers.first.id;
    if (amount == null || amount < s.minDeposit || amount > s.maxDeposit) {
      setState(() => _error = 'Enter an amount from ${PlayMode.money(s.minDeposit, decimals: 0)} to ${PlayMode.money(s.maxDeposit, decimals: 0)}.');
      return;
    }
    final cubit = context.read<LiveCubit>();
    setState(() {
      _busy = true;
      _error = null;
      _unfinished = null;
      _phase = 'Starting payment...';
    });
    try {
      var p = await cubit.api.deposit(provider: provider, amount: amount, key: _key);
      if (p.status != 'succeeded' && p.status != 'failed') {
        if (!s.mock) {
          // A real gateway opens its own checkout here (Paystack / Stripe SDK) using p.checkout.
          throw const ApiException(501, 'not_wired', 'This payment method is not connected yet.');
        }
        if (!mounted) return;
        final label = providers.firstWhere((x) => x.id == provider).label;
        final paid = await showMockGateway(context, provider: label, amount: amount, deposit: true);
        if (!mounted) return;
        if (paid == null) {
          setState(() {
            _unfinished = p;
            _error = 'Payment not finished. You can complete it later from your wallet. You will not be charged twice.';
          });
          return;
        }
        setState(() => _phase = 'Confirming with $label...');
        await cubit.api.mockPay(p.id, success: paid);
        p = await _settle(cubit, p.id);
      }
      if (!mounted) return;
      switch (p.status) {
        case 'succeeded':
          _key = LiveCubit.newKey();
          AppSound.play(Sfx.win);
          setState(() => _done = '${PlayMode.money(p.amount)} added to your live balance.');
        case 'failed':
          _key = LiveCubit.newKey();
          setState(() => _error = 'The payment was declined. Nothing was charged.');
        case 'flagged':
          setState(() => _error = 'We need to check this payment. It will show in your wallet once reviewed.');
        default:
          setState(() {
            _unfinished = p;
            _error = 'Still waiting for the provider. Check your wallet in a moment. Do not pay again.';
          });
      }
    } on ApiException catch (e) {
      // A dropped connection keeps the same key: trying again is safe and can't charge twice.
      if (mounted) setState(() => _error = e.isNetwork ? 'No connection. Tap Pay again; you will not be charged twice.' : e.message);
    } finally {
      cubit.refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LiveCubit>().state.status;
    if (s == null) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()));
    final providers = [for (final p in s.providers) if (p.deposit && _availableHere(p.id)) p];
    final chosen = _provider ?? (providers.isEmpty ? null : providers.first.id);

    if (_done != null) {
      return Column(children: [
        Icon(Icons.check_circle_rounded, size: 64, color: AppColors.green),
        const SizedBox(height: 12),
        Text(_done!, textAlign: TextAlign.center, style: AppText.body(16, weight: FontWeight.w700)),
        const SizedBox(height: 20),
        AppButton(label: 'Done', variant: AppButtonVariant.gold, onPressed: () => Navigator.of(context).pop()),
      ]);
    }

    return PopScope(
      canPop: !_busy, // can't close the sheet while a payment is being confirmed
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (s.mock) ...[
            InfoCard(message: 'Test mode: payments are simulated, no real money moves.', icon: Icons.science_outlined, color: AppColors.blue),
            const SizedBox(height: 14),
          ],
          Text('AMOUNT (${s.currency})', style: AppText.label()),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final v in const [1000, 2000, 5000, 10000, 20000, 50000])
              if (v >= s.minDeposit && v <= s.maxDeposit)
                PillChip(label: PlayMode.money(v, decimals: 0), selected: _value == v.toDouble(), onTap: _busy ? null : () => setState(() => _amount.text = '$v')),
          ]),
          const SizedBox(height: 12),
          AppTextField(
            label: 'Other amount',
            controller: _amount,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 16),
          Text('PAY WITH', style: AppText.label()),
          const SizedBox(height: 8),
          ProviderPicker(providers: providers, chosen: chosen, onChanged: _busy ? null : (id) => setState(() => _provider = id)),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: AppText.body(13, color: AppColors.loss, height: 1.4)),
          ],
          const SizedBox(height: 18),
          AppButton(
            label: _busy ? _phase : 'Pay ${_value == null ? '' : PlayMode.money(_value!, decimals: 0)}',
            variant: AppButtonVariant.gold,
            loading: _busy,
            onPressed: _busy || providers.isEmpty ? null : () => _pay(s, providers),
          ),
          if (_unfinished != null) ...[
            const SizedBox(height: 8),
            Center(child: TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: Text('Close and check later', style: AppText.body(13, color: AppColors.textMuted)))),
          ],
        ],
      ),
    );
  }
}
