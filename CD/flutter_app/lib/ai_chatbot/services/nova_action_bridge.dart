import 'package:flutter/foundation.dart';

/// Typed, allowlisted handoff emitted by Nova after the backend validates a
/// completed tool result. The host app can listen to [lastAction] and route it
/// to its existing Trip/Map/Weather/Community/Profile owner without Nova
/// importing or controlling those modules.
class NovaAction {
  const NovaAction({
    required this.type,
    required this.target,
    required this.parameters,
    required this.requiresConfirmation,
  });

  final String type;
  final String target;
  final Map<String, dynamic> parameters;
  final bool requiresConfirmation;

  static NovaAction? fromJson(Object? value) {
    if (value is! Map) return null;
    final type = value['type'];
    final target = value['target'];
    final parameters = value['parameters'];
    final confirmation = value['requires_confirmation'];
    const allowedTargets = <String, String>{
      'start_journey': 'trip',
      'show_place_results': 'map',
      'weather_display': 'weather',
      'community_results': 'community',
      'preferences_updated': 'profile',
    };
    if (type is! String || target is! String || confirmation is! bool) {
      return null;
    }
    if (allowedTargets[type] != target || parameters is! Map) return null;
    final safeParameters = _safeParametersForAction(type, parameters);
    if (safeParameters == null) return null;
    return NovaAction(
      type: type,
      target: target,
      parameters: safeParameters,
      requiresConfirmation: confirmation,
    );
  }

  static Map<String, dynamic>? _safeParameters(Map value) {
    if (value.length > 32) return null;
    final result = <String, dynamic>{};
    for (final entry in value.entries) {
      if (entry.key is! String || entry.key.length > 80) return null;
      if (!_isSafeJsonValue(entry.value, depth: 0)) return null;
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static Map<String, dynamic>? _safeParametersForAction(
    String type,
    Map value,
  ) {
    final safe = _safeParameters(value);
    if (safe == null) return null;

    bool hasOnly(Set<String> keys) =>
        safe.keys.every(keys.contains) && safe.length == keys.length;
    bool hasRequiredAndOnly({
      required Set<String> required,
      required Set<String> allowed,
    }) => required.every(safe.containsKey) && safe.keys.every(allowed.contains);
    String? requiredString(String key, {int maxLength = 160}) {
      final value = safe[key];
      if (value is! String ||
          value.trim().isEmpty ||
          value.length > maxLength) {
        return null;
      }
      return value;
    }

    bool optionalString(String key, {int maxLength = 160}) {
      final value = safe[key];
      return value is String && value.length <= maxLength;
    }

    bool stringList(String key, {int maxItems = 24, int maxLength = 80}) {
      final value = safe[key];
      return value is List &&
          value.length <= maxItems &&
          value.every((item) => item is String && item.length <= maxLength);
    }

    switch (type) {
      case 'start_journey':
      case 'show_place_results':
        if (!hasRequiredAndOnly(
              required: const {
                'destination',
                'interests',
                'budget',
                'duration',
              },
              allowed: const {
                'destination',
                'interests',
                'budget',
                'duration',
                'trip_mode',
              },
            ) ||
            requiredString('destination') == null ||
            !stringList('interests') ||
            !optionalString('budget', maxLength: 80)) {
          return null;
        }
        final duration = safe['duration'];
        if (duration != null || !safe.containsKey('duration')) {
          if (duration is! num ||
              !duration.isFinite ||
              duration <= 0 ||
              duration > 365) {
            return null;
          }
        }
        final tripMode = safe['trip_mode'];
        if (tripMode != null && tripMode != 'solo') {
          return null;
        }
        return safe;
      case 'weather_display':
        if (!hasOnly(const {'location', 'date', 'weather', 'observed_at'}) ||
            requiredString('location') == null ||
            requiredString('date') == null ||
            requiredString('weather') == null ||
            requiredString('observed_at') == null) {
          return null;
        }
        return safe;
      case 'community_results':
        return hasOnly(const {'query'}) && requiredString('query') != null
            ? safe
            : null;
      case 'preferences_updated':
        return hasOnly(const {
                  'favorite_categories',
                  'travel_style',
                  'budget_preference',
                }) &&
                stringList('favorite_categories') &&
                optionalString('travel_style', maxLength: 120) &&
                optionalString('budget_preference', maxLength: 120)
            ? safe
            : null;
    }
    return null;
  }

  static bool _isSafeJsonValue(Object? value, {required int depth}) {
    if (depth > 4 || value == null || value is bool) return depth <= 4;
    if (value is num) return value.isFinite;
    if (value is String) return value.length <= 2000;
    if (value is List) {
      return value.length <= 50 &&
          value.every((item) => _isSafeJsonValue(item, depth: depth + 1));
    }
    if (value is Map) {
      return value.length <= 32 &&
          value.entries.every(
            (entry) =>
                entry.key is String &&
                (entry.key as String).length <= 80 &&
                _isSafeJsonValue(entry.value, depth: depth + 1),
          );
    }
    return false;
  }
}

class NovaActionBridge {
  NovaActionBridge._();

  static final ValueNotifier<NovaAction?> lastAction = ValueNotifier(null);

  static NovaAction? publish(Object? payload) {
    final action = NovaAction.fromJson(payload);
    lastAction.value = action;
    return action;
  }

  static void clear() => lastAction.value = null;
}
