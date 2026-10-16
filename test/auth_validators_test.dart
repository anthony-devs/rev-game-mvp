import 'package:flutter_test/flutter_test.dart';
import 'package:rev_game_mvp/auth/data/auth_failure.dart';
import 'package:rev_game_mvp/auth/data/auth_validators.dart';

void main() {
  test('email', () {
    expect(AuthValidators.email(''), isNotNull);
    expect(AuthValidators.email('nope'), isNotNull);
    expect(AuthValidators.email('a@b'), isNotNull);
    expect(AuthValidators.email(' you@example.com '), isNull);
  });

  test('password and name', () {
    expect(AuthValidators.password('12345'), isNotNull);
    expect(AuthValidators.password('123456'), isNull);
    expect(AuthValidators.name(' '), isNotNull);
    expect(AuthValidators.name('Ann'), isNull);
  });

  test('phone numbers become E.164', () {
    expect(AuthValidators.countryCode('+234'), isNull);
    expect(AuthValidators.countryCode('234'), isNotNull);
    expect(AuthValidators.phoneNumber('12'), isNotNull);
    expect(AuthValidators.e164('+234', '0801 234 5678'), '+2348012345678');
    expect(AuthValidators.e164('+1', '415-555-0100'), '+14155550100');
  });

  test('failures map to friendly messages', () {
    expect(AuthFailure.fromCode('wrong-password').message, contains('Wrong email'));
    expect(AuthFailure.fromCode('something-new').message, contains('Something went wrong'));
    expect(const AuthFailure.cancelled().cancelled, isTrue);
  });
}
