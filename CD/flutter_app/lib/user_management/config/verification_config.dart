class VerificationConfig {
  VerificationConfig._();

  // Android Studio's standard emulator reaches the host laptop via 10.0.2.2.
  // Override this for a physical phone with:
  // --dart-define=VERIFICATION_API_URL=http://192.168.x.x:8000
  static const String backendUrl = String.fromEnvironment(
    'VERIFICATION_API_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );
}
