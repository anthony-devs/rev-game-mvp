import 'package:flutter/foundation.dart';

import 'formatters.dart';

/// Demo credits or live (real money). One switch for the whole app.
///
/// The profile cubit flips it; widgets that show money listen to [live], and the API
/// client sends it with every request so the server plays on the right wallet.
class PlayMode {
  PlayMode._();

  static final ValueNotifier<bool> live = ValueNotifier<bool>(false);
  static bool get isLive => live.value;

  /// Symbol shown in front of live amounts. The server's currency decides it.
  static String symbol = '₦';

  static const Map<String, String> _symbols = {'NGN': '₦', 'USD': r'$', 'GBP': '£', 'EUR': '€', 'GHS': 'GH₵', 'KES': 'KSh '};

  static void setCurrency(String code) => symbol = _symbols[code.toUpperCase()] ?? '${code.toUpperCase()} ';

  /// `₦5,000.00` in live mode, `5,000.00` in demo.
  static String amount(num v, {int decimals = 2}) => isLive ? money(v, decimals: decimals) : formatCredits(v, decimals: decimals);

  /// Always with the currency symbol.
  static String money(num v, {int decimals = 2}) => '$symbol${formatCredits(v, decimals: decimals)}';
}
