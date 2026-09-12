import 'package:flutter/foundation.dart';

/// Provider-level state only. It intentionally contains no Android engine
/// details and never owns the request microphone or the Agent pipeline.
enum NovaWakeWordProviderPhase {
  idle,
  starting,
  listening,
  stopped,
  unavailable,
  error,
}

class NovaWakeWordProviderState {
  const NovaWakeWordProviderState({
    this.phase = NovaWakeWordProviderPhase.idle,
    this.reason,
  });

  final NovaWakeWordProviderPhase phase;
  final String? reason;
}

/// Shared status surface for the native openWakeWord provider boundary.
/// A future model integration only reports a local wake event through this
/// contract; it must then hand off to [NovaInvocationManager].
class NovaWakeWordProvider {
  NovaWakeWordProvider._();

  static final ValueNotifier<NovaWakeWordProviderState> state =
      ValueNotifier<NovaWakeWordProviderState>(
        const NovaWakeWordProviderState(),
      );

  static void update(NovaWakeWordProviderPhase phase, {String? reason}) {
    state.value = NovaWakeWordProviderState(phase: phase, reason: reason);
  }
}
