import 'package:equatable/equatable.dart';

import '../model/model_json.dart';

class LiveProvider extends Equatable {
  const LiveProvider({required this.id, required this.label, required this.deposit, required this.payout});
  final String id, label;
  final bool deposit, payout;

  factory LiveProvider.fromJson(Json j) => LiveProvider(
        id: parseString(j['id']) ?? '',
        label: parseString(j['label']) ?? '',
        deposit: j['deposit'] == true,
        payout: j['payout'] == true,
      );

  @override
  List<Object?> get props => [id, label, deposit, payout];
}

class LivePayment extends Equatable {
  const LivePayment({
    required this.id,
    required this.kind,
    required this.provider,
    required this.amount,
    required this.currency,
    required this.status,
    this.createdAt,
    this.reference = '',
    this.note = '',
    this.bank = '',
    this.accountLast4 = '',
    this.checkoutRef = '',
  });

  final String id, kind, provider, currency, status, reference, note, bank, accountLast4, checkoutRef;
  final double amount;
  final DateTime? createdAt;

  bool get isDeposit => kind == 'deposit';

  /// Still moving: the player may need to act (deposit) or wait (payout).
  bool get open => isDeposit ? (status == 'created' || status == 'pending') : (status == 'pending_review' || status == 'processing');

  String get statusLabel => switch (status) {
        'created' => 'Starting',
        'pending' => 'Waiting for payment',
        'succeeded' => 'Completed',
        'failed' => 'Failed',
        'flagged' => 'Under review',
        'pending_review' => 'Waiting for approval',
        'processing' => 'Being sent',
        'paid' => 'Paid',
        'rejected' => 'Returned to wallet',
        _ => status,
      };

  factory LivePayment.fromJson(Json j) {
    final dest = parseMap(j['destination']);
    final checkout = parseMap(j['checkout']);
    return LivePayment(
      id: parseString(j['id']) ?? '',
      kind: parseString(j['kind']) ?? 'deposit',
      provider: parseString(j['provider']) ?? '',
      amount: parseDouble(j['amount']),
      currency: parseString(j['currency']) ?? '',
      status: parseString(j['status']) ?? '',
      createdAt: DateTime.tryParse(parseString(j['createdAt']) ?? ''),
      reference: parseString(j['reference']) ?? '',
      note: parseString(j['note']) ?? '',
      bank: parseString(dest['bankName']) ?? '',
      accountLast4: parseString(dest['accountLast4']) ?? '',
      checkoutRef: parseString(checkout['ref']) ?? '',
    );
  }

  @override
  List<Object?> get props => [id, status, amount, updatedKey];
  String get updatedKey => '$status$note';
}

class LiveStatus extends Equatable {
  const LiveStatus({
    required this.enabled,
    this.message = '',
    this.currency = 'NGN',
    this.mock = true,
    this.balance = 0,
    this.minDeposit = 500,
    this.maxDeposit = 500000,
    this.minPayout = 1000,
    this.maxPayout = 1000000,
    this.providers = const [],
    this.openPayouts = 0,
    this.pendingDeposits = const [],
  });

  final bool enabled, mock;
  final String message, currency;
  final double balance, minDeposit, maxDeposit, minPayout, maxPayout;
  final List<LiveProvider> providers;
  final int openPayouts;
  final List<LivePayment> pendingDeposits;

  factory LiveStatus.fromJson(Json j) {
    final lim = parseMap(j['limits']);
    return LiveStatus(
      enabled: j['enabled'] == true,
      message: parseString(j['message']) ?? '',
      currency: parseString(j['currency']) ?? 'NGN',
      mock: j['mock'] == true,
      balance: parseDouble(j['balance']),
      minDeposit: parseDouble(lim['minDeposit']),
      maxDeposit: parseDouble(lim['maxDeposit']),
      minPayout: parseDouble(lim['minPayout']),
      maxPayout: parseDouble(lim['maxPayout']),
      providers: [for (final p in (j['providers'] as List? ?? const [])) LiveProvider.fromJson(parseMap(p))],
      openPayouts: parseInt(j['openPayouts']),
      pendingDeposits: [for (final p in (j['pendingDeposits'] as List? ?? const [])) LivePayment.fromJson(parseMap(p))],
    );
  }

  @override
  List<Object?> get props => [enabled, message, currency, mock, balance, providers, openPayouts, pendingDeposits];
}
