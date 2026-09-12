import 'package:flutter_app/ai_chatbot/services/nova_action_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
