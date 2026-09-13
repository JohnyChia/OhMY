import 'package:flutter_app/ai_chatbot/services/nova_action_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps matching tags attached to each recommendation page', () {
    final action = NovaAction.fromJson({
      'type': 'show_place_results',
      'target': 'map',
      'parameters': {
        'destination': 'Kuala Lumpur',
        'interests': ['Nature', 'Cultural Experience'],
        'budget': '',
        'duration': null,
        'recommendations': [
          {
            'matchedPreferences': ['Cultural Experience'],
            'ranking': {'matchingTags': ['Historical Landmark']},
          },
          {
            'matchedPreferences': ['Nature'],
            'ranking': {'matchingTags': ['Park']},
          },
        ],
      },
      'requires_confirmation': false,
    });

    final recommendations = action!.parameters['recommendations'] as List;
    expect(recommendations[0]['analysis']['generalTags'], [
      'Cultural Experience',
      'Historical Landmark',
    ]);
    expect(recommendations[1]['analysis']['generalTags'], ['Nature', 'Park']);
  });

  test('accepts a Start Trip chooser action without a trip mode', () {
    final action = NovaAction.fromJson({
      'type': 'start_journey',
      'target': 'trip',
      'parameters': {
        'destination': 'Sabah',
        'interests': <String>[],
        'budget': '',
        'duration': null,
      },
      'requires_confirmation': false,
    });

    expect(action, isNotNull);
    expect(action!.parameters['destination'], 'Sabah');
    expect(action.parameters.containsKey('trip_mode'), isFalse);
  });

  test('still accepts an explicit valid trip mode', () {
    final action = NovaAction.fromJson({
      'type': 'start_journey',
      'target': 'trip',
      'parameters': {
        'destination': 'Sabah',
        'interests': <String>['Nature'],
        'budget': '',
        'duration': null,
        'trip_mode': 'solo',
      },
      'requires_confirmation': false,
    });

    expect(action?.parameters['trip_mode'], 'solo');
  });

  test('rejects an unsupported trip mode', () {
    final action = NovaAction.fromJson({
      'type': 'start_journey',
      'target': 'trip',
      'parameters': {
        'destination': 'Sabah',
        'interests': <String>[],
        'budget': '',
        'duration': null,
        'trip_mode': 'private',
      },
      'requires_confirmation': false,
    });

    expect(action, isNull);
  });

  test('rejects Travel Group handoff from Nova', () {
    final action = NovaAction.fromJson({
      'type': 'start_journey',
      'target': 'trip',
      'parameters': {
        'destination': 'Sabah',
        'interests': <String>[],
        'budget': '',
        'duration': null,
        'trip_mode': 'group',
      },
      'requires_confirmation': false,
    });

    expect(action, isNull);
  });
}
