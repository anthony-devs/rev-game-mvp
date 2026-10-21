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

bool _availableHere(String id) {
  if (id == 'apple_pay') return defaultTargetPlatform == TargetPlatform.iOS;
  if (id == 'google_pay') return defaultTargetPlatform == TargetPlatform.android;
  return true;
}

String _when(DateTime t) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '${t.day} ${months[t.month - 1]} ${t.year}, $h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
}

/// The full "add money" checkout: amount, payment method, order summary, pay, receipt.
/// Payments still run through the same server calls as before (simulated until the real gateways are connected).
class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _amount = TextEditingController(text: '5000');
  String? _provider;

  /// One key per attempt: retries of the same attempt can never create a second payment.
  String _key = LiveCubit.newKey();
  bool _busy = false;
  String? _error;
  String _phase = '';
  LivePayment? _unfinished;
  LivePayment? _receipt;
  String _receiptMethod = '';
  DateTime? _paidAt;

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
    if (_busy) return;
    final amount = _value;
    final provider = _provider ?? providers.first.id;
    if (amount == null || amount < s.minDeposit || amount > s.maxDeposit) {
      setState(() => _error = 'Enter an amount from ${PlayMode.money(s.minDeposit, decimals: 0)} to ${PlayMode.money(s.maxDeposit, decimals: 0)}.');
      return;
    }
    final cubit = context.read<LiveCubit>();
    final label = providers.firstWhere((x) => x.id == provider).label;
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
          throw const ApiException(501, 'not_wired', 'This payment method is not connected yet.');
        }
        if (!mounted) return;
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
          setState(() {
            _receipt = p;
            _receiptMethod = label;
            _paidAt = DateTime.now();
          });
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
      if (mounted) setState(() => _error = e.isNetwork ? '${e.message} Tap Pay again; you will not be charged twice.' : e.message);
    } finally {
      cubit.refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LiveCubit>().state.status;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: s == null
                  ? const Padding(padding: EdgeInsets.all(20), child: SkeletonList(rows: 4, rowHeight: 72))
                  : (_receipt != null ? _receiptView(s) : _checkoutView(s)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(String title, {bool back = true}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 20, 8),
      child: Row(children: [
        if (back) IconSquareButton(icon: Icons.chevron_left_rounded, semanticLabel: 'Back', size: 40, iconSize: 22, onPressed: _busy ? null : () => Navigator.of(context).pop()) else const SizedBox(width: 4),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: AppText.body(20, weight: FontWeight.w800))),
        Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.green),
        const SizedBox(width: 6),
        Text('Secure checkout', style: AppText.body(12, color: AppColors.textMuted)),
      ]),
    );
  }

  Widget _section(String step, String title) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Row(children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
            child: Text(step, style: AppText.body(12, weight: FontWeight.w800, color: AppColors.onAccent, height: 1)),
          ),
          const SizedBox(width: 10),
          Text(title, style: AppText.body(15, weight: FontWeight.w800)),
        ]),
      );

  Widget _checkoutView(LiveStatus s) {
    final providers = [for (final p in s.providers) if (p.deposit && _availableHere(p.id)) p];
    final chosen = providers.where((p) => p.id == _provider).firstOrNull ?? (providers.isEmpty ? null : providers.first);
    final amount = _value;
    final quote = (amount == null || chosen == null) ? '' : chosen.payText(amount);
    return Column(children: [
      _header('Checkout'),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
          if (s.mock) ...[
            const SizedBox(height: 8),
            InfoCard(message: 'Test mode: payments are simulated, no real money moves.', icon: Icons.science_outlined, color: AppColors.blue),
          ],
          _section('1', 'Amount (${s.currency})'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final v in const [1000, 2000, 5000, 10000, 20000, 50000])
              if (v >= s.minDeposit && v <= s.maxDeposit)
                PillChip(label: PlayMode.money(v, decimals: 0), selected: amount == v.toDouble(), onTap: _busy ? null : () => setState(() { _amount.text = '$v'; _error = null; })),
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
          const SizedBox(height: 6),
          Text('Minimum ${PlayMode.money(s.minDeposit, decimals: 0)}  ·  Maximum ${PlayMode.money(s.maxDeposit, decimals: 0)}', style: AppText.body(12, color: AppColors.textDim)),
          _section('2', 'Payment method'),
          if (providers.isEmpty)
            Text('No payment methods are available right now.', style: AppText.body(14, color: AppColors.textMuted))
          else
            for (final p in providers) _MethodTile(provider: p, selected: p.id == chosen?.id, onTap: _busy ? null : () => setState(() => _provider = p.id)),
          _section('3', 'Order summary'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.line)),
            child: Column(children: [
              _Line('Deposit to live balance', amount == null ? '-' : PlayMode.money(amount, decimals: 0)),
              _Line('Processing fee', (chosen?.fee.isNotEmpty ?? false) ? chosen!.fee : 'None'),
              if (chosen != null && chosen.eta.isNotEmpty) _Line('Arrives', chosen.eta),
              if (quote.isNotEmpty) _Line('You pay', quote),
              Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, color: AppColors.line)),
              Row(children: [
                Text('Total', style: AppText.body(15, weight: FontWeight.w800)),
                const Spacer(),
                Text(amount == null ? '-' : PlayMode.money(amount, decimals: 0), style: AppText.number(20, color: AppColors.gold)),
              ]),
            ]),
          ),
          if (chosen != null && chosen.isCrypto) ...[
            const SizedBox(height: 10),
            Text('Send only ${chosen.payCurrency} on the ${chosen.network} network. Money sent on a different network is lost.', style: AppText.body(12, color: AppColors.loss, height: 1.4)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: AppText.body(13, color: AppColors.loss, height: 1.4)),
          ],
          const SizedBox(height: 14),
          Text('Your payment is handled by our payment partner. We never see or store your card details.', style: AppText.body(12, color: AppColors.textDim, height: 1.4)),
        ]),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        decoration: BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.line))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppButton(
            label: _busy ? _phase : 'Pay ${amount == null ? '' : PlayMode.money(amount, decimals: 0)}',
            variant: AppButtonVariant.gold,
            icon: _busy ? null : Icons.lock_rounded,
            loading: _busy,
            onPressed: (_busy || providers.isEmpty) ? null : () => _pay(s, providers),
          ),
          if (_unfinished != null)
            TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: Text('Close and check later', style: AppText.body(13, color: AppColors.textMuted))),
        ]),
      ),
    ]);
  }

  Widget _receiptView(LiveStatus s) {
    final p = _receipt!;
    final ref = p.reference.isNotEmpty ? p.reference : p.id;
    return Column(children: [
      _header('Payment complete', back: false),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 20), children: [
          Icon(Icons.check_circle_rounded, size: 76, color: AppColors.green),
          const SizedBox(height: 14),
          Text('Payment successful', textAlign: TextAlign.center, style: AppText.body(22, weight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('${PlayMode.money(p.amount)} was added to your live balance.', textAlign: TextAlign.center, style: AppText.body(14, color: AppColors.textMuted, height: 1.4)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.line)),
            child: Column(children: [
              _Line('Amount', PlayMode.money(p.amount)),
              _Line('Method', _receiptMethod),
              _Line('Status', 'Successful'),
              _Line('Date', _when(_paidAt ?? DateTime.now())),
              _Line('Reference', ref),
            ]),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: AppButton(label: 'Start playing', variant: AppButtonVariant.gold, onPressed: () => Navigator.of(context).pop()),
      ),
    ]);
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({required this.provider, required this.selected, required this.onTap});

  final LiveProvider provider;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final detail = [if (provider.eta.isNotEmpty) provider.eta, if (provider.fee.isNotEmpty) provider.fee].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PressScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? AppColors.gold.withValues(alpha: .08) : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? AppColors.gold : AppColors.line, width: selected ? 1.6 : 1),
          ),
          child: Row(children: [
            PaymentLogo(provider.id, width: 56, height: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(provider.label, style: AppText.body(15, weight: FontWeight.w700)),
                if (provider.blurb.isNotEmpty) Text(provider.blurb, style: AppText.body(12, color: AppColors.textMuted)),
                if (detail.isNotEmpty) Text(detail, style: AppText.body(11, color: AppColors.textDim)),
              ]),
            ),
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, color: selected ? AppColors.gold : AppColors.textDim),
          ]),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppText.body(13, color: AppColors.textDim)),
          const SizedBox(width: 16),
          Expanded(child: Text(value, textAlign: TextAlign.right, style: AppText.body(13, weight: FontWeight.w600))),
        ]),
      );
}
