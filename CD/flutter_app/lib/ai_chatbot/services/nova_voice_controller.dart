import 'dart:async';

import 'package:flutter/foundation.dart';

enum NovaVoicePhase {
  idle,
  invocationDetected,
  prompting,
  listening,
  processing,
  thinking,
  executing,
  awaitingConfirmation,
  speaking,
  completed,
  interrupted,
  error,
}

/// Every present and future entry point must identify itself before entering
/// Nova's shared voice/session pipeline. Unsupported sources are contracts,
/// not claims that the capability is already implemented.
enum NovaInvocationSource {
  foregroundWake,
  manualMicrophone,
  chatbotMicrophone,
  futureSystemWake,
  futureBluetooth,
  futureCarIntegration,
}

class NovaVoiceState {
  const NovaVoiceState({
    this.phase = NovaVoicePhase.idle,
    this.message,
    this.response,
    this.amplitude = 0,
    this.sessionId,
    this.source,
    this.languageCode = 'en',
  });

  final NovaVoicePhase phase;
  final String? message;
  final String? response;
  final double amplitude;
  final String? sessionId;
  final NovaInvocationSource? source;
  final String languageCode;

  NovaVoiceState copyWith({
    NovaVoicePhase? phase,
    String? message,
    String? response,
    double? amplitude,
    String? sessionId,
    NovaInvocationSource? source,
    String? languageCode,
    bool clearMessage = false,
    bool clearResponse = false,
  }) => NovaVoiceState(
    phase: phase ?? this.phase,
    message: clearMessage ? null : (message ?? this.message),
    response: clearResponse ? null : (response ?? this.response),
    amplitude: amplitude ?? this.amplitude,
    sessionId: sessionId ?? this.sessionId,
    source: source ?? this.source,
    languageCode: languageCode ?? this.languageCode,
  );
}

class NovaVoiceInvocation {
  const NovaVoiceInvocation({
    required this.sessionId,
    required this.source,
    this.wakePhrase,
    this.announce = false,
  });

  final String sessionId;
  final NovaInvocationSource source;

  /// The locally detected wake phrase. It is UI/session metadata only and
  /// must never be sent to the Travel Agent as a user request.
  final String? wakePhrase;

  /// A wake-word invocation receives a short spoken greeting before Nova
  /// opens the microphone for the actual request. Manual mic taps do not.
  final bool announce;
}

/// App-wide bridge for the Nova microphone. Any module can ask the AI tab to
/// start a voice session without importing or owning the chat screen state.
class NovaVoiceController {
  NovaVoiceController._();

  static const wakePrompt = 'Hi! What can I help you with?';

  static final ValueNotifier<int> startRequests = ValueNotifier<int>(0);
  static final ValueNotifier<NovaVoiceState> state =
      ValueNotifier<NovaVoiceState>(const NovaVoiceState());
  static NovaVoiceInvocation? _pendingInvocation;
  static int _sessionSequence = 0;
  static Timer? _autoResetTimer;

  static void requestVoiceSession({
    String? wakePhrase,
    bool announce = false,
    NovaInvocationSource source = NovaInvocationSource.manualMicrophone,
  }) {
    final sessionId =
        'nova-${DateTime.now().microsecondsSinceEpoch}-${++_sessionSequence}';
    _pendingInvocation = NovaVoiceInvocation(
      sessionId: sessionId,
      source: source,
      wakePhrase: wakePhrase,
      announce: announce,
    );
    update(
      phase: NovaVoicePhase.invocationDetected,
      message: 'Nova is ready.',
      clearResponse: true,
      sessionId: sessionId,
      source: source,
    );
    startRequests.value++;
  }

  static NovaVoiceInvocation? takePendingInvocation() {
    final invocation = _pendingInvocation;
    _pendingInvocation = null;
    return invocation;
  }

  static void requestInterrupt() {
    update(
      phase: NovaVoicePhase.interrupted,
      message: 'Listening for your next request…',
    );
    requestVoiceSession(source: NovaInvocationSource.foregroundWake);
  }

  static void update({
    NovaVoicePhase? phase,
    String? message,
    String? response,
    double? amplitude,
    String? sessionId,
    NovaInvocationSource? source,
    String? languageCode,
    bool clearMessage = false,
    bool clearResponse = false,
  }) {
    _autoResetTimer?.cancel();
    state.value = state.value.copyWith(
      phase: phase,
      message: message,
      response: response,
      amplitude: amplitude,
      sessionId: sessionId,
      source: source,
      languageCode: languageCode,
      clearMessage: clearMessage,
      clearResponse: clearResponse,
    );
    final nextPhase = state.value.phase;
    if (nextPhase == NovaVoicePhase.completed ||
        nextPhase == NovaVoicePhase.error ||
        nextPhase == NovaVoicePhase.interrupted) {
      _autoResetTimer = Timer(const Duration(seconds: 3), () {
        if (state.value.phase == nextPhase) reset();
      });
    }
  }

  static void reset() {
    _autoResetTimer?.cancel();
    _autoResetTimer = null;
    state.value = const NovaVoiceState();
  }
}
