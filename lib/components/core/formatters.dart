/// Credits with thousands separators: `formatCredits(91250)` -> `91,250.00`.
String formatCredits(num value, {int decimals = 2}) {
  final fixed = value.toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final neg = parts[0].startsWith('-');
  final digits = neg ? parts[0].substring(1) : parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  final whole = '${neg ? '-' : ''}$buf';
  return decimals > 0 ? '$whole.${parts[1]}' : whole;
}

/// `+2,420` / `-1,000`. Zero has no sign.
String formatSigned(num value, {int decimals = 0}) {
  final s = formatCredits(value.abs(), decimals: decimals);
  if (value > 0) return '+$s';
  if (value < 0) return '-$s';
  return s;
}

/// `3.42x`. Whole numbers drop the decimals when [trim] is true.
String formatMultiplier(num value, {int decimals = 2, bool trim = false}) {
  if (trim && value == value.roundToDouble()) return '${value.round()}x';
  return '${value.toStringAsFixed(decimals)}x';
}

/// `12m 04s` style countdown from seconds.
String formatCountdown(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return m > 0 ? '${m}m ${s.toString().padLeft(2, '0')}s' : '${s}s';
}
