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

    test('rejects prohibited symbols and malformed addresses', () {
      const invalidEmails = [
        'name+tag@example.com',
        'name%tag@example.com',
        '.name@example.com',
        'name..test@example.com',
        'name@example',
        'name@-example.com',
        'name@example.c',
        'name @example.com',
      ];

      for (final email in invalidEmails) {
        expect(AuthValidators.email(email), isNotNull, reason: email);
      }
    });

    test('accepts supported separators and subdomains', () {
      expect(AuthValidators.email('first.last@example.com'), isNull);
      expect(AuthValidators.email('student_01@mail.example.edu.my'), isNull);
      expect(AuthValidators.email('user-name@example.com'), isNull);
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

  group('AuthValidators.username', () {
    test('accepts supported usernames', () {
      expect(AuthValidators.username('Traveller_23'), isNull);
      expect(AuthValidators.username('Aina123'), isNull);
    });

    test('rejects spaces, symbols and invalid lengths', () {
      expect(AuthValidators.username('A B'), isNotNull);
      expect(AuthValidators.username('23traveller'), isNotNull);
      expect(AuthValidators.username('user-name'), isNotNull);
      expect(AuthValidators.username('ab'), isNotNull);
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
