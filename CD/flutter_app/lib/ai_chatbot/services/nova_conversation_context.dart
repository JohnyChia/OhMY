import 'package:flutter/foundation.dart';

import 'nova_action_bridge.dart';
import 'nova_voice_controller.dart';

/// Client-side, non-persistent context for visual continuity between Nova
/// turns. Durable conversation, trip, and preference memory remains owned by
/// the backend and existing product modules.
class NovaConversationSnapshot {
  const NovaConversationSnapshot({
    this.sessionId,
    this.source,
    this.currentPage,
    this.lastUserMessage,
    this.lastAssistantMessage,
    this.lastAction,
  });

  final String? sessionId;
  final NovaInvocationSource? source;
  final String? currentPage;
  final String? lastUserMessage;
  final String? lastAssistantMessage;
  final NovaAction? lastAction;

  NovaConversationSnapshot copyWith({
    String? sessionId,
    NovaInvocationSource? source,
    String? currentPage,
    String? lastUserMessage,
    String? lastAssistantMessage,
    NovaAction? lastAction,
  }) => NovaConversationSnapshot(
    sessionId: sessionId ?? this.sessionId,
    source: source ?? this.source,
    currentPage: currentPage ?? this.currentPage,
    lastUserMessage: lastUserMessage ?? this.lastUserMessage,
    lastAssistantMessage: lastAssistantMessage ?? this.lastAssistantMessage,
    lastAction: lastAction ?? this.lastAction,
  );
}

class NovaConversationContext {
  NovaConversationContext._();

  static final ValueNotifier<NovaConversationSnapshot> snapshot =
      ValueNotifier<NovaConversationSnapshot>(const NovaConversationSnapshot());

  static void beginSession({
    required String sessionId,
    required NovaInvocationSource source,
  }) {
    snapshot.value = NovaConversationSnapshot(
      sessionId: sessionId,
      source: source,
    );
  }

  /// Page owners can opt in later without coupling Nova to module routes.
  static void updateCurrentPage(String page) {
    final normalized = page.trim();
    if (normalized.isEmpty) return;
    snapshot.value = snapshot.value.copyWith(currentPage: normalized);
  }

  static void recordUserTurn(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    snapshot.value = snapshot.value.copyWith(lastUserMessage: normalized);
  }

  static void recordAssistantTurn(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    snapshot.value = snapshot.value.copyWith(lastAssistantMessage: normalized);
  }

  static void recordAction(NovaAction? action) {
    if (action == null) return;
    snapshot.value = snapshot.value.copyWith(lastAction: action);
  }
}
