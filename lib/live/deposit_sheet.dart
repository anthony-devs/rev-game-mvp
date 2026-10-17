import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../components/components.dart';
import '../core/api/api_client.dart';
import '../games/game_support.dart' show showToast;
import 'agreement_page.dart';
import 'live_cubit.dart';
import 'live_models.dart';
import 'mock_gateway.dart';
import 'method_list.dart';
import 'payment_logo.dart';

Future<void> showDepositSheet(BuildContext context) async {
  // The status may be missing (app restarted in live mode). Load it first so the sheet never hangs.
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
  String? _provider; // null = still choosing a method

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
      if (mounted) setState(() => _error = e.isNetwork ? '${e.message} Tap Pay again; you will not be charged twice.' : e.message);
    } finally {
      cubit.refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LiveCubit>().state.status;
    if (s == null) return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: SkeletonList(rows: 4, rowHeight: 56));
    final providers = [for (final p in s.providers) if (p.deposit && _availableHere(p.id)) p];

    if (_done != null) {
      return Column(children: [
        Icon(Icons.check_circle_rounded, size: 64, color: AppColors.green),
        const SizedBox(height: 12),
        Text(_done!, textAlign: TextAlign.center, style: AppText.body(16, weight: FontWeight.w700)),
        const SizedBox(height: 20),
        AppButton(label: 'Done', variant: AppButtonVariant.gold, onPressed: () => Navigator.of(context).pop()),
      ]);
    }

    final chosen = providers.where((p) => p.id == _provider).firstOrNull;
    if (chosen == null) {
      // Step 1: how do you want to pay?
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (s.mock) ...[
            InfoCard(message: 'Test mode: payments are simulated, no real money moves.', icon: Icons.science_outlined, color: AppColors.blue),
            const SizedBox(height: 14),
          ],
          Text('Choose how to add money', style: AppText.body(14, color: AppColors.textMuted)),
          const SizedBox(height: 12),
          if (providers.isEmpty)
            Text('No payment methods are available right now.', style: AppText.body(14, color: AppColors.textMuted))
          else
            MethodList(providers: providers, onPick: (p) => setState(() => _provider = p.id)),
        ],
      );
    }

    // Step 2: how much?
    final quote = _value == null ? '' : chosen.payText(_value!);
    return PopScope(
      canPop: !_busy, // can't close the sheet while a payment is being confirmed
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            IconSquareButton(icon: Icons.chevron_left_rounded, semanticLabel: 'Back', size: 40, iconSize: 22, onPressed: _busy ? null : () => setState(() => _provider = null)),
            const SizedBox(width: 12),
            PaymentLogo(chosen.id, width: 52, height: 36),
            const SizedBox(width: 10),
            Expanded(child: Text(chosen.label, style: AppText.body(16, weight: FontWeight.w800))),
          ]),
          const SizedBox(height: 16),
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
          const SizedBox(height: 12),
          _Facts(rows: [
            ('Minimum', PlayMode.money(s.minDeposit, decimals: 0)),
            ('Maximum', PlayMode.money(s.maxDeposit, decimals: 0)),
            if (chosen.eta.isNotEmpty) ('Time', chosen.eta),
            if (chosen.fee.isNotEmpty) ('Fee', chosen.fee),
            if (quote.isNotEmpty) ('You pay', '$quote  (1 ${chosen.payCurrency} = ${PlayMode.money(chosen.rate, decimals: 0)})'),
            if (chosen.isCrypto) ('Network', chosen.network),
          ]),
          if (chosen.isCrypto) ...[
            const SizedBox(height: 10),
            Text('Send only ${chosen.payCurrency} on the ${chosen.network} network. Money sent on a different network is lost.', style: AppText.body(12, color: AppColors.loss, height: 1.4)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: AppText.body(13, color: AppColors.loss, height: 1.4)),
          ],
          const SizedBox(height: 18),
          AppButton(
            label: _busy ? _phase : 'Pay ${_value == null ? '' : PlayMode.money(_value!, decimals: 0)}',
            variant: AppButtonVariant.gold,
            loading: _busy,
            onPressed: _busy ? null : () => _pay(s, providers),
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

/// A small table of facts (limits, time, fee) under the amount.
class _Facts extends StatelessWidget {
  const _Facts({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Column(children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.$1, style: AppText.body(12.5, color: AppColors.textDim)),
              const SizedBox(width: 16),
              Expanded(child: Text(r.$2, textAlign: TextAlign.right, style: AppText.body(12.5, weight: FontWeight.w600))),
            ]),
          ),
      ]),
    );
  }
}
