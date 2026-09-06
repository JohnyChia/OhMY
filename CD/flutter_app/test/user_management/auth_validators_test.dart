import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/user_management/utils/auth_validators.dart';

void main() {
  group('AuthValidators.email', () {
    test('accepts a valid email', () {
      expect(AuthValidators.email('traveller@example.com'), isNull);
    });

    test('rejects an invalid email', () {
      expect(AuthValidators.email('traveller'), isNotNull);
    });
  });

  group('AuthValidators.password', () {
    test('accepts 8 to 16 alphanumeric characters', () {
      expect(AuthValidators.password('Travel123'), isNull);
    });

    test('rejects short and non-alphanumeric passwords', () {
      expect(AuthValidators.password('short'), isNotNull);
      expect(AuthValidators.password('Travel@123'), isNotNull);
    });
  });

  group('AuthValidators', () {
    test('requires a six-digit OTP', () {
      expect(AuthValidators.otp('123456'), isNull);
      expect(AuthValidators.otp('12345'), isNotNull);
    });

    test('requires a 3 to 30 character full name', () {
      expect(AuthValidators.fullName('A Traveller'), isNull);
      expect(AuthValidators.fullName('A'), isNotNull);
    });
  });
}
