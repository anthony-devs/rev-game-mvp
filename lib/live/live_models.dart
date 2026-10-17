import 'package:equatable/equatable.dart';

import '../model/model_json.dart';

/// One way to pay in or get paid out. The server decides which exist and what they say.
class LiveProvider extends Equatable {
  const LiveProvider({
    required this.id,
    required this.label,
    required this.deposit,
    required this.payout,
    this.category = 'cards',
    this.blurb = '',
    this.eta = '',
    this.fee = '',
    this.payCurrency = '',
    this.rate = 1,
    this.destination = 'bank',
    this.network = '',
  });

  final String id, label, category, blurb, eta, fee, payCurrency, destination, network;
  final bool deposit, payout;

  /// Wallet units for one unit of [payCurrency] (USDT, USD). 1 when the method pays in the wallet currency.
  final double rate;

  bool get isCrypto => category == 'crypto';
  bool get convertsCurrency => payCurrency.isNotEmpty && rate > 0;

  /// What the player really pays for [walletAmount], e.g. `10.0000 USDT`.
  String payText(double walletAmount) {
    if (!convertsCurrency) return '';
    final v = walletAmount / rate;
    return '${v.toStringAsFixed(payCurrency == 'USD' ? 2 : 4)} $payCurrency';
  }

  factory LiveProvider.fromJson(Json j) => LiveProvider(
        id: parseString(j['id']) ?? '',
        label: parseString(j['label']) ?? '',
        deposit: j['deposit'] == true,
        payout: j['payout'] == true,
        category: parseString(j['category']) ?? 'cards',
        blurb: parseString(j['blurb']) ?? '',
        eta: parseString(j['eta']) ?? '',
        fee: parseString(j['fee']) ?? '',
        payCurrency: parseString(j['payCurrency']) ?? '',
        rate: parseDouble(j['rate'], 1),
        destination: parseString(j['destination']) ?? 'bank',
        network: parseString(j['network']) ?? '',
      );

  @override
  List<Object?> get props => [id, label, deposit, payout, category, rate];
}

/// The Live Money Agreement, as the server sends it.
class LiveAgreement extends Equatable {
  const LiveAgreement({required this.version, required this.title, required this.intro, required this.sections, required this.confirmations, required this.accepted});

  final String version, title, intro;
  final List<({String title, String body})> sections;
  final List<({String id, String text})> confirmations;
  final bool accepted;

  factory LiveAgreement.fromJson(Json j) => LiveAgreement(
        version: parseString(j['version']) ?? '1',
        title: parseString(j['title']) ?? 'Live Money Agreement',
        intro: parseString(j['intro']) ?? '',
        sections: [
          for (final s in (j['sections'] as List? ?? const [])) (title: parseString(parseMap(s)['title']) ?? '', body: parseString(parseMap(s)['body']) ?? ''),
        ],
        confirmations: [
          for (final c in (j['confirmations'] as List? ?? const [])) (id: parseString(parseMap(c)['id']) ?? '', text: parseString(parseMap(c)['text']) ?? ''),
        ],
        accepted: j['accepted'] == true,
      );

  @override
  List<Object?> get props => [version, accepted];
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
    this.masked = '',
  });

  final String id, kind, provider, currency, status, reference, note, bank, accountLast4, checkoutRef, masked;
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
      masked: parseString(dest['masked']) ?? '',
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
    this.agreementRequired = false,
    this.agreementAccepted = true,
  });

  final bool enabled, mock;
  final String message, currency;
  final double balance, minDeposit, maxDeposit, minPayout, maxPayout;
  final List<LiveProvider> providers;
  final int openPayouts;
  final List<LivePayment> pendingDeposits;

  /// The player must accept the Live Money Agreement before live play.
  final bool agreementRequired, agreementAccepted;

  bool get needsAgreement => agreementRequired && !agreementAccepted;

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
      agreementRequired: parseMap(j['agreement'])['required'] == true,
      agreementAccepted: parseMap(j['agreement'])['accepted'] != false,
    );
  }

  @override
  List<Object?> get props => [enabled, message, currency, mock, balance, providers, openPayouts, pendingDeposits, agreementRequired, agreementAccepted];
}
