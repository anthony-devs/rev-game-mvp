/// Form checks. Each returns an error message, or `null` when the value is fine.
class AuthValidators {
  AuthValidators._();

  static final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  static final RegExp _code = RegExp(r'^\+\d{1,4}$');

  static String? email(String value) {
    final v = value.trim();
    if (v.isEmpty) return 'Enter your email';
    if (!_email.hasMatch(v)) return 'Enter a valid email';
    return null;
  }

  static String? password(String value) {
    if (value.isEmpty) return 'Enter your password';
    if (value.length < 6) return 'At least 6 characters';
    return null;
  }

  static String? name(String value) {
    final v = value.trim();
    if (v.isEmpty) return 'Enter your name';
    if (v.length < 2) return 'Name is too short';
    return null;
  }

  static String? countryCode(String value) {
    if (!_code.hasMatch(value.trim())) return 'Use a code like +234';
    return null;
  }

  static String? phoneNumber(String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return 'Enter your phone number';
    if (digits.length < 6 || digits.length > 14) return 'Enter a valid number';
    return null;
  }

  /// Builds an E.164 number: "+234" + "0801 234 5678" -> "+2348012345678".
  static String e164(String countryCode, String number) {
    var digits = number.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) digits = digits.substring(1);
    return '${countryCode.trim()}$digits';
  }
}
