import 'package:flutter/services.dart';

typedef NovaBargeInHandler =
    Future<void> Function(String transcript, bool isFinal);
typedef NovaBargeInSpeechStartedHandler = Future<void> Function();

/// Android's bounded foreground recognizer used while Nova is speaking. It is
/// not a background wake-word implementation. Each visible owner decides
/// whether a final transcript is a route choice, reroute answer, or chat turn.
class NovaBargeInService {
  NovaBargeInService._();

  static const MethodChannel _channel = MethodChannel('ohmy/nova_barge_in');
  static bool _initialized = false;
  static NovaBargeInHandler? _handler;
  static NovaBargeInSpeechStartedHandler? _speechStartedHandler;

  static void _initialize() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'bargeInSpeechStarted') {
        await _speechStartedHandler?.call();
        return;
      }
      if (call.method != 'bargeInTranscript') return;
      final arguments = call.arguments;
      final transcript = arguments is Map
          ? arguments['transcript']?.toString().trim() ?? ''
          : '';
      final isFinal = arguments is Map && arguments['isFinal'] == true;
      if (transcript.isNotEmpty) await _handler?.call(transcript, isFinal);
    });
  }

  static Future<bool> start({
    required String languageCode,
    required NovaBargeInHandler onTranscript,
    NovaBargeInSpeechStartedHandler? onSpeechStarted,
  }) async {
    _initialize();
    _handler = onTranscript;
    _speechStartedHandler = onSpeechStarted;
    try {
      return await _channel.invokeMethod<bool>('startBargeIn', {
            'languageCode': languageCode,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> stop() async {
    _handler = null;
    _speechStartedHandler = null;
    try {
      await _channel.invokeMethod<void>('stopBargeIn');
    } on MissingPluginException {
      // Barge-in is Android-only; post-narration voice remains available.
    } on PlatformException {
      // A recognizer shutdown failure must not block route confirmation.
    }
  }
}
