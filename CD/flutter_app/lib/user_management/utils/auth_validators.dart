class AuthValidators {
  AuthValidators._();

  static String? requiredField(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter $fieldName.';
    }
    return null;
  }

  static String? email(String? value) {
    final requiredError = requiredField(value, 'your email address');
    if (requiredError != null) return requiredError;

    final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!emailPattern.hasMatch(value!.trim())) {
      return 'Please enter a valid email address.';
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

  static String? otp(String? value) {
    if (!RegExp(r'^\d{6}$').hasMatch(value?.trim() ?? '')) {
      return 'Enter the 6-digit code from your email.';
    }
    return null;
  }
}
