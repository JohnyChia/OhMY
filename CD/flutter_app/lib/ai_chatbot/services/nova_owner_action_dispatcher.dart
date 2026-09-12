import 'package:flutter/foundation.dart';

import 'nova_action_bridge.dart';

/// Outcome of forwarding a Nova action to the module that owns it.
///
/// A validated action is not considered executed until its registered owner
/// completes the handoff. This keeps Nova from claiming that navigation or a
/// module-specific UI update happened when no owner contract exists.
enum NovaOwnerActionStatus { executed, unavailable, rejected, failed }

class NovaOwnerActionResult {
  const NovaOwnerActionResult({
    required this.action,
    required this.status,
    required this.message,
    this.errorCode,
  });

  final NovaAction action;
  final NovaOwnerActionStatus status;
  final String message;
  final String? errorCode;

  bool get executed => status == NovaOwnerActionStatus.executed;
}

typedef NovaOwnerActionHandler =
    Future<NovaOwnerActionResult> Function(NovaAction action);

class NovaOwnerActionRegistration {
  NovaOwnerActionRegistration._(this._target, this._handler);

  final String _target;
  final NovaOwnerActionHandler _handler;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    NovaOwnerActionDispatcher._unregister(_target, _handler);
  }
}

/// Central, typed integration seam between Nova and independently owned UI
/// modules. Module owners opt in by registering one handler for their target;
/// Nova never imports, mutates, or reimplements their business logic.
///
/// Until an owner registers a handler, dispatch deliberately reports
/// [NovaOwnerActionStatus.unavailable]. It does not fake navigation.
class NovaOwnerActionDispatcher {
  NovaOwnerActionDispatcher._();

  static const _allowedActionsByTarget = <String, Set<String>>{
    'trip': {'start_journey'},
    'map': {'show_place_results'},
    'weather': {'weather_display'},
    'community': {'community_results'},
    'profile': {'preferences_updated'},
  };

  static final Map<String, NovaOwnerActionHandler> _handlers =
      <String, NovaOwnerActionHandler>{};

  static final ValueNotifier<NovaOwnerActionResult?> lastResult =
      ValueNotifier<NovaOwnerActionResult?>(null);

  static NovaOwnerActionRegistration register({
    required String target,
    required NovaOwnerActionHandler handler,
  }) {
    if (!_allowedActionsByTarget.containsKey(target)) {
      throw ArgumentError.value(target, 'target', 'Unsupported Nova target.');
    }
    if (_handlers.containsKey(target)) {
      throw StateError(
        'A Nova owner handler is already registered for $target.',
      );
    }
    _handlers[target] = handler;
    return NovaOwnerActionRegistration._(target, handler);
  }

  static void _unregister(String target, NovaOwnerActionHandler handler) {
    if (identical(_handlers[target], handler)) _handlers.remove(target);
  }

  static NovaOwnerActionResult rejectedPayload() => NovaOwnerActionResult(
    action: const NovaAction(
      type: 'invalid_action',
      target: 'invalid',
      parameters: <String, dynamic>{},
      requiresConfirmation: false,
    ),
    status: NovaOwnerActionStatus.rejected,
    message: 'NOT EXECUTED — INVALID ACTION PAYLOAD',
    errorCode: 'INVALID_ACTION_PAYLOAD',
  );

  static Future<NovaOwnerActionResult?> dispatch(NovaAction? action) async {
    if (action == null) return null;
    if (!(_allowedActionsByTarget[action.target]?.contains(action.type) ??
        false)) {
      final result = NovaOwnerActionResult(
        action: action,
        status: NovaOwnerActionStatus.rejected,
        message: 'NOT EXECUTED — ACTION TARGET REJECTED (${action.target})',
        errorCode: 'ACTION_TARGET_REJECTED',
      );
      lastResult.value = result;
      return result;
    }
    final handler = _handlers[action.target];
    if (handler == null) {
      final result = NovaOwnerActionResult(
        action: action,
        status: NovaOwnerActionStatus.unavailable,
        message: 'NOT EXECUTED — OWNER CONTRACT MISSING (${action.target})',
        errorCode: 'OWNER_CONTRACT_MISSING',
      );
      lastResult.value = result;
      return result;
    }

    try {
      final result = await handler(action);
      if (result.action.type != action.type ||
          result.action.target != action.target) {
        final rejected = NovaOwnerActionResult(
          action: action,
          status: NovaOwnerActionStatus.rejected,
          message: 'NOT EXECUTED — OWNER RETURNED A CONFLICTING ACTION',
          errorCode: 'OWNER_ACTION_MISMATCH',
        );
        lastResult.value = rejected;
        return rejected;
      }
      lastResult.value = result;
      return result;
    } catch (_) {
      final result = NovaOwnerActionResult(
        action: action,
        status: NovaOwnerActionStatus.failed,
        message: 'NOT EXECUTED — OWNER HANDOFF FAILED (${action.target})',
        errorCode: 'OWNER_HANDOFF_FAILED',
      );
      lastResult.value = result;
      return result;
    }
  }
}
