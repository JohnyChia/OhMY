import 'package:flutter/services.dart';

class AuthValidators {
  AuthValidators._();

  static List<TextInputFormatter> get emailInputFormatters => [
    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9@._-]')),
    LengthLimitingTextInputFormatter(254),
  ];

  static List<TextInputFormatter> get usernameInputFormatters => [
    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
    LengthLimitingTextInputFormatter(20),
  ];

  static String? requiredField(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter $fieldName.';
    }
    return null;
  }

  static String? email(String? value) {
    final requiredError = requiredField(value, 'your email address');
    if (requiredError != null) return requiredError;

    final email = value!.trim();
    final parts = email.split('@');
    if (parts.length != 2 || parts.first.length > 64) {
      return 'Enter a valid email such as name@example.com.';
    }

    // Project rule: keep addresses simple and predictable. The local part can
    // contain letters/numbers with single dots, underscores, or hyphens between
    // them. Symbols such as + and % are deliberately not accepted.
    final emailPattern = RegExp(
      r'^[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*@'
      r'[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?'
      r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*'
      r'\.[A-Za-z]{2,63}$',
    );
    if (!emailPattern.hasMatch(email)) {
      return 'Enter a valid email without symbols such as + or %.';
    }
    return null;
  }

  static String? password(String? value) {
    final requiredError = requiredField(value, 'your password');
    if (requiredError != null) return requiredError;

    final passwordPattern = RegExp(r'^[A-Za-z0-9]{8,16}$');
    if (!passwordPattern.hasMatch(value!)) {
      return 'Use 8–16 letters and numbers only.';
    }
    return null;
  }

  static String? fullName(String? value) {
    final requiredError = requiredField(value, 'your full name');
    if (requiredError != null) return requiredError;

    final length = value!.trim().length;
    if (length < 3 || length > 30) {
      return 'Name must contain 3–30 characters.';
    }
    return null;
  }

  static String? username(String? value) {
    final requiredError = requiredField(value, 'a username');
    if (requiredError != null) return requiredError;

    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]{2,19}$').hasMatch(value!.trim())) {
      return 'Use 3–20 letters, numbers or underscores; start with a letter.';
    }
    return null;
  }

  static String? otp(String? value) {
    if (!RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '')) {
      return 'Enter the 6-digit code from your email.';
    }
    return null;
  }
}
