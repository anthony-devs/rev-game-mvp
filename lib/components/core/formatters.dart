/// Coins with thousands separators: `formatCredits(91250)` -> `91,250.00`.
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

/// Short form for big numbers in tight spaces: `1.25M`, `3.4B`. Under a million it is the usual
/// `formatCredits`. Rounds down, so it never shows more than the player has.
String formatCompact(num value, {int decimals = 2}) {
  final a = value.abs();
  if (a < 1e6) return formatCredits(value, decimals: decimals);
  final (div, unit) = a >= 1e12 ? (1e12, 'T') : (a >= 1e9 ? (1e9, 'B') : (1e6, 'M'));
  final scaled = (a / div * 100).floor() / 100;
  var s = scaled.toStringAsFixed(2);
  if (s.contains('.')) s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return '${value < 0 ? '-' : ''}$s$unit';
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
