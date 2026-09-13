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

    test('rejects overlong addresses and domain labels', () {
      final overlongLabel = 'a@${'x' * 64}.com';
      final overlongAddress =
          '${'a' * 64}@${'b' * 63}.${'c' * 63}.${'d' * 63}.com';

      expect(AuthValidators.email(overlongLabel), isNotNull);
      expect(AuthValidators.email(overlongAddress), isNotNull);
    });

    test('does not silently remove invalid pasted symbols', () {
      final formatter = AuthValidators.emailInputFormatters.first;
      const pasted = TextEditingValue(text: 'name+tag@gmail.com');

      expect(
        formatter.formatEditUpdate(TextEditingValue.empty, pasted).text,
        pasted.text,
      );
      expect(AuthValidators.email(pasted.text), isNotNull);
    });
  });

  group('AuthValidators.canonicalEmail', () {
    test('treats Gmail dot aliases as the same account', () {
      expect(
        AuthValidators.canonicalEmail(' Y.Lynnnnx@Gmail.com '),
        'ylynnnnx@gmail.com',
      );
      expect(
        AuthValidators.canonicalEmail('ylynnnn.x@googlemail.com'),
        'ylynnnnx@gmail.com',
      );
    });

    test('preserves dots and hyphens for other providers', () {
      expect(
        AuthValidators.canonicalEmail('first.last@tarc.edu.my'),
        'first.last@tarc.edu.my',
      );
      expect(
        AuthValidators.canonicalEmail('chanyl-wm23@student.tarc.edu.my'),
        'chanyl-wm23@student.tarc.edu.my',
      );
    });
  });

  group('AuthValidators.password', () {
    test('accepts 8 to 20 alphanumeric characters', () {
      expect(AuthValidators.password('Travel123'), isNull);
      expect(AuthValidators.password('LongTravelPassword1'), isNull);
    });

    test('rejects short and non-alphanumeric passwords', () {
      expect(AuthValidators.password('short'), isNotNull);
      expect(AuthValidators.password('Travel@123'), isNotNull);
    });

    test('requires uppercase, lowercase, and a number', () {
      expect(AuthValidators.password('abcdefgh'), isNotNull);
      expect(AuthValidators.password('12345678'), isNotNull);
      expect(AuthValidators.password('abcd1234'), isNotNull);
      expect(AuthValidators.password('ABCD1234'), isNotNull);
      expect(AuthValidators.password('Abcd1234'), isNull);
    });

    test('rejects the old password regardless of letter case', () {
      expect(
        AuthValidators.newPassword('QQQQ1111', oldPassword: 'qqqq1111'),
        isNotNull,
      );
      expect(
        AuthValidators.newPassword('Travel5678', oldPassword: 'Travel1234'),
        isNull,
      );
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
