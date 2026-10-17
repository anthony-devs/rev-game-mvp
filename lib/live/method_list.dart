import 'package:flutter/material.dart';

import '../components/components.dart';
import 'live_models.dart';
import 'payment_logo.dart';

const _groups = <(String, String)>[
  ('bank', 'Bank'),
  ('crypto', 'Crypto'),
  ('wallet', 'E-wallets'),
  ('cards', 'Cards'),
];

/// Payment methods in groups (Bank, Crypto, E-wallets, Cards), each row showing the method's logo,
/// what it is, how long it takes and what it costs. Used to choose how to add or withdraw money.
class MethodList extends StatelessWidget {
  const MethodList({super.key, required this.providers, required this.onPick});

  final List<LiveProvider> providers;
  final ValueChanged<LiveProvider> onPick;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final (key, title) in _groups) {
      final rows = [for (final p in providers) if (p.category == key) p];
      if (rows.isEmpty) continue;
      children
        ..add(Padding(padding: const EdgeInsets.only(top: 6, bottom: 8), child: Text(title.toUpperCase(), style: AppText.label())))
        ..addAll([for (final p in rows) _Row(provider: p, onTap: () => onPick(p))]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.provider, required this.onTap});

  final LiveProvider provider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final detail = [if (provider.eta.isNotEmpty) provider.eta, if (provider.fee.isNotEmpty) provider.fee].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PressScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
          child: Row(
            children: [
              PaymentLogo(provider.id, width: 56, height: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(provider.label, style: AppText.body(15, weight: FontWeight.w700)),
                    if (provider.blurb.isNotEmpty) Text(provider.blurb, style: AppText.body(12, color: AppColors.textMuted)),
                    if (detail.isNotEmpty) ...[const SizedBox(height: 2), Text(detail, style: AppText.body(11, color: AppColors.textDim))],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }
}
