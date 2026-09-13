import 'package:flutter_app/ai_chatbot/services/nova_action_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'recommendation selection preserves the place and waits for Start Journey',
    () {
      final action = NovaAction.forRecommendedPlace({
        'id': 'selected-id',
        'name': 'Selected restaurant',
        'address': 'Setapak',
        'location': {'latitude': 3.2, 'longitude': 101.72},
      });
      expect(action, isNotNull);
      expect(action!.requiresConfirmation, isTrue);
      expect(action.parameters['destination_kind'], 'place');
      expect(action.parameters['place_id'], 'selected-id');
      expect(action.parameters['latitude'], 3.2);
      expect(action.parameters['trip_mode'], 'solo');
    },
  );

  test(
    'unverified recommendation cannot be passed as an exact route endpoint',
    () {
      expect(NovaAction.forRecommendedPlace({'name': 'Unknown'}), isNull);
      expect(
        NovaAction.forRecommendedPlace({
          'name': 'Invalid',
          'location': {'latitude': 999, 'longitude': 101},
        }),
        isNull,
      );
    },
  );
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

  test('rejects Group Trip handoff from Nova', () {
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

  test('accepts a resolved specific place for automatic navigation', () {
    final action = NovaAction.fromJson({
      'type': 'start_journey',
      'target': 'trip',
      'parameters': {
        'destination': 'Setapak Central',
        'interests': <String>[],
        'budget': '',
        'duration': null,
        'destination_kind': 'place',
        'place_id': 'setapak-central-id',
        'address': 'Setapak, Kuala Lumpur',
        'latitude': 3.2048773,
        'longitude': 101.7202996,
      },
      'requires_confirmation': false,
    });

    expect(action, isNotNull);
    expect(action!.parameters['destination_kind'], 'place');
    expect(action.parameters['latitude'], 3.2048773);
  });

  test('accepts a broad area as search-only map handoff', () {
    final action = NovaAction.fromJson({
      'type': 'show_place_results',
      'target': 'map',
      'parameters': {
        'destination': 'Penang',
        'interests': <String>[],
        'budget': '',
        'duration': null,
        'destination_kind': 'area',
      },
      'requires_confirmation': false,
    });

    expect(action, isNotNull);
    expect(action!.parameters['destination_kind'], 'area');
  });
}
