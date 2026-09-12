import 'package:flutter/services.dart';

import 'nova_voice_controller.dart';
import 'nova_wake_word_provider.dart';

/// Foreground integration boundary for an approved, on-device wake detector.
/// No microphone recording or audio upload happens here. A future Android/iOS
/// host implementation can notify this channel after it has obtained consent
/// and detected a wake phrase locally.
class NovaInvocationManager {
  NovaInvocationManager._();

  static const MethodChannel _channel = MethodChannel('ohmy/nova_invocation');
  static bool _initialized = false;
  static bool _wakeListenerActive = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      final arguments = call.arguments;
      switch (call.method) {
        case 'wakeWordDetected':
          final source = arguments is Map
              ? arguments['source']?.toString()
              : null;
          final phrase = arguments is Map
              ? arguments['phrase']?.toString()
              : null;
          await _handleWakeWordDetected(source: source, phrase: phrase);
          break;
        case 'wakeProviderStarted':
          NovaWakeWordProvider.update(NovaWakeWordProviderPhase.listening);
          break;
        case 'wakeProviderStopped':
          if (NovaWakeWordProvider.state.value.phase !=
              NovaWakeWordProviderPhase.unavailable) {
            NovaWakeWordProvider.update(NovaWakeWordProviderPhase.stopped);
          }
          break;
        case 'wakeProviderUnavailable':
          _wakeListenerActive = false;
          NovaWakeWordProvider.update(
            NovaWakeWordProviderPhase.unavailable,
            reason: arguments is Map ? arguments['reason']?.toString() : null,
          );
          break;
        case 'wakeProviderError':
          _wakeListenerActive = false;
          NovaWakeWordProvider.update(
            NovaWakeWordProviderPhase.error,
            reason: arguments is Map ? arguments['reason']?.toString() : null,
          );
          break;
        case 'foregroundInvocationDetected':
          _wakeListenerActive = false;
          await stopForegroundWakeListener();
          // Legacy-only bridge. The native recognizer is retained temporarily
          // but its transcript is deliberately never passed to the Agent.
          NovaVoiceController.requestVoiceSession(
            announce: true,
            source: NovaInvocationSource.foregroundWake,
          );
          break;
        case 'foregroundWakePermissionDenied':
          _wakeListenerActive = false;
          NovaVoiceController.update(
            phase: NovaVoicePhase.error,
            message: 'Microphone permission is needed to wake Nova.',
          );
          break;
        case 'foregroundWakeError':
          _wakeListenerActive = false;
          NovaVoiceController.update(
            phase: NovaVoicePhase.error,
            message:
                'Voice wake is unavailable. You can use Nova’s mic button.',
          );
          break;
        case 'foregroundListeningStarted':
          NovaVoiceController.update(
            phase: NovaVoicePhase.listening,
            message: 'Listening for “Hi Nova”…',
            clearResponse: true,
          );
          break;
        case 'interrupt':
          NovaVoiceController.requestInterrupt();
          break;
      }
    });
  }

  /// Contract for a real on-device wake provider. Only a provider that has
  /// already detected one of the supported phrases may call this event.
  static Future<void> _handleWakeWordDetected({
    required String? source,
    required String? phrase,
  }) async {
    final normalized = phrase?.trim().toLowerCase();
    if (source != 'wake_word' ||
        (normalized != 'hey nova' && normalized != 'hi nova')) {
      return;
    }
    _wakeListenerActive = false;
    await stopForegroundWakeListener();
    final phase = NovaVoiceController.state.value.phase;
    if (phase == NovaVoicePhase.speaking || phase == NovaVoicePhase.prompting) {
      // A genuine wake event while Nova talks is an interruption. The shared
      // controller invalidates stale TTS/API callbacks before it reopens the
      // normal recorder, without replaying the greeting.
      NovaVoiceController.requestInterrupt();
      return;
    }
    NovaVoiceController.requestVoiceSession(
      wakePhrase: normalized,
      announce: true,
      source: NovaInvocationSource.foregroundWake,
    );
  }

  static Future<void> startForegroundWakeListener() async {
    if (_wakeListenerActive) return;
    _wakeListenerActive = true;
    NovaWakeWordProvider.update(NovaWakeWordProviderPhase.starting);
    try {
      await _channel.invokeMethod<void>('startForegroundWakeListener');
    } catch (_) {
      _wakeListenerActive = false;
    }
  }

  static Future<void> stopForegroundWakeListener() async {
    _wakeListenerActive = false;
    try {
      await _channel.invokeMethod<void>('stopForegroundWakeListener');
    } catch (_) {
      // The optional host wake implementation must not break manual voice.
    }
  }
}
