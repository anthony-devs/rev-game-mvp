import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../components/components.dart';
import 'live_models.dart';

/// Brand marks live in `assets/logos/`. Paystack and Flutterwave have no bundled artwork yet,
/// so they show a coloured wordmark; drop `paystack.svg` / `flutterwave.svg` into that folder,
/// list them in [_assets] and they are used instead.
const Map<String, String> _assets = {
  'stripe': 'assets/logos/stripe.svg',
  'apple_pay': 'assets/logos/apple_pay.svg',
  'google_pay': 'assets/logos/google_pay.svg',
};

const Map<String, (String, Color)> _wordmarks = {
  'paystack': ('paystack', Color(0xFF00C3F7)),
  'flutterwave': ('flutterwave', Color(0xFFFB9129)),
  'paypal': ('PayPal', Color(0xFF003087)),
};

const Map<String, String> _subtitles = {
  'paystack': 'Cards, bank transfer, USSD',
  'flutterwave': 'Cards, bank, mobile money',
  'stripe': 'Visa, Mastercard',
  'apple_pay': 'Pay with Face ID',
  'google_pay': 'Pay with your Google account',
};

/// The logo on a white tile, so brand colours read the same in dark and light mode.
class PaymentLogo extends StatelessWidget {
  const PaymentLogo(this.id, {super.key, this.width = 64, this.height = 34});

  final String id;
  final double width, height;

  @override
  Widget build(BuildContext context) {
    final asset = _assets[id];
    final word = _wordmarks[id];
    Widget child;
    if (id.startsWith('usdt')) {
      // Tether's green coin. The network (TRC20, BEP20...) is written in the method's name.
      child = Container(
        width: height * .62,
        height: height * .62,
        alignment: Alignment.center,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF26A17B)),
        child: const Text('\u20AE', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800, height: 1)),
      );
    } else if (id == 'bank_ng') {
      child = const Icon(Icons.account_balance_rounded, size: 20, color: Color(0xFF1B3A6B));
    } else if (asset != null) {
      child = SvgPicture.asset(asset, height: height * 0.56, fit: BoxFit.contain, placeholderBuilder: (_) => const SizedBox.shrink());
    } else if (word != null) {
      child = FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(word.$1, style: TextStyle(color: word.$2, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
      );
    } else {
      child = Icon(Icons.account_balance_wallet_outlined, size: 18, color: Colors.black54);
    }
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0x14000000))),
      child: child,
    );
  }
}

/// A selectable row: logo, name, short description, radio.
class ProviderTile extends StatelessWidget {
  const ProviderTile({super.key, required this.provider, required this.selected, required this.onTap});

  final LiveProvider provider;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.gold : AppColors.lineStrong, width: selected ? 1.6 : 1),
        ),
        child: Row(children: [
          PaymentLogo(provider.id),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(provider.label, style: AppText.body(14, weight: FontWeight.w700)),
              if ((provider.blurb.isNotEmpty ? provider.blurb : _subtitles[provider.id]) != null)
                Text(provider.blurb.isNotEmpty ? provider.blurb : _subtitles[provider.id]!, style: AppText.body(12, color: AppColors.textMuted)),
            ]),
          ),
          Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: 22, color: selected ? AppColors.gold : AppColors.textMuted),
        ]),
      ),
    );
  }
}

/// A column of [ProviderTile]s.
class ProviderPicker extends StatelessWidget {
  const ProviderPicker({super.key, required this.providers, required this.chosen, required this.onChanged});

  final List<LiveProvider> providers;
  final String? chosen;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (final p in providers)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ProviderTile(provider: p, selected: chosen == p.id, onTap: onChanged == null ? null : () => onChanged!(p.id)),
          ),
      ]);
}
