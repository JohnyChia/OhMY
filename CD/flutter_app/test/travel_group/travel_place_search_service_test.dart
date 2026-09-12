import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_app/travel_group/features/travel_group/models/travel_group_models.dart';
import 'package:flutter_app/travel_group/features/travel_group/services/travel_place_search_service.dart';

void main() {
  test('area search asks for and retains only general area results', () async {
    late Map<String, dynamic> requestBody;
    final service = TravelPlaceSearchService(
      backendUrl: 'http://example.test',
      client: MockClient((request) async {
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'places': [
              {
                'id': 'areas/shah-alam',
                'displayName': {'text': 'Shah Alam'},
                'formattedAddress': 'Selangor, Malaysia',
                'location': {'latitude': 3.0738, 'longitude': 101.5183},
                'isArea': true,
              },
              {
                'id': 'places/a-mall',
                'displayName': {'text': 'A Mall'},
                'formattedAddress': 'Shah Alam, Selangor',
                'location': {'latitude': 3.07, 'longitude': 101.52},
                'isArea': false,
              },
            ],
          }),
          200,
        );
      }),
    );

    final results = await service.search('Shah Alam', areasOnly: true);

    expect(requestBody['areasOnly'], isTrue);
    expect(results.map((item) => item.name), ['Shah Alam']);
  });

  test(
    'nearby recommendations use group preferences and expose photo metadata',
    () async {
      late Map<String, dynamic> requestBody;
      final service = TravelPlaceSearchService(
        backendUrl: 'http://example.test',
        client: MockClient((request) async {
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'matchedPlaces': [
                {
                  'matchedPreferences': ['Cultural Experience'],
                  'place': {
                    'id': 'places/forum',
                    'displayName': {'text': 'Sunsuria Forum'},
                    'primaryType': 'shopping_mall',
                    'distanceKm': 0.9,
                    'photo': {'name': 'places/forum/photos/first'},
                    'location': {'latitude': 3.1, 'longitude': 101.5},
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final results = await service.nearbySuggestions(
        latitude: 3.1,
        longitude: 101.5,
        destinationPlaceId: 'places/setia-city-mall',
        preferences: const ['Cultural Experience'],
      );

      expect(requestBody['mode'], 'preferences');
      expect(requestBody['preferences'], ['Cultural Experience']);
      expect(requestBody['excludePlaceId'], 'places/setia-city-mall');
      expect(results.single.category, 'Cultural Experience');
      expect(results.single.tags, ['Cultural Experience']);
      expect(results.single.photoName, 'places/forum/photos/first');
    },
  );

  test(
    'raw Google place types are converted to readable fallback labels',
    () async {
      final service = TravelPlaceSearchService(
        backendUrl: 'http://example.test',
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'matchedPlaces': [
                {
                  'matchedPreferences': [],
                  'place': {
                    'id': 'places/hardware',
                    'displayName': {'text': 'Hardware Shop'},
                    'primaryType': 'hardware_store',
                    'distanceKm': 1.1,
                    'location': {'latitude': 3.1, 'longitude': 101.5},
                  },
                },
              ],
            }),
            200,
          ),
        ),
      );

      final results = await service.nearbySuggestions(
        latitude: 3.1,
        longitude: 101.5,
        preferences: const ['Traditional Craft'],
      );

      expect(results.single.category, 'Hardware store');
      expect(results.single.tags, ['Hardware store']);
      expect(results.single.category, isNot(contains('_')));
    },
  );

  test(
    'recommendations move from the first destination to the latest visited stop',
    () {
      final group = TravelGroup(
        id: 'group',
        creatorId: 'creator',
        creatorName: 'Creator',
        name: 'Setia group',
        destination: 'Setia City Mall',
        description: 'Explore nearby places',
        meetupPoint: '',
        tags: const ['Cultural Experience'],
        maxMembers: 4,
        distanceKm: 0,
        joinMode: JoinMode.open,
        status: GroupStatus.waiting,
        memberIds: const ['creator'],
        destinationPlaceId: 'places/setia-city-mall',
        destinationLatitude: 3.109,
        destinationLongitude: 101.46,
      );
      final stops = [
        ItineraryStop(
          id: 'one',
          groupId: 'group',
          suggestionId: '',
          placeName: 'Setia City Mall',
          placeId: 'places/setia-city-mall',
          latitude: 3.109,
          longitude: 101.46,
          position: 0,
          estimatedDurationMinutes: 0,
          travelTimeFromPreviousMinutes: 0,
          status: StopStatus.completed,
        ),
        ItineraryStop(
          id: 'two',
          groupId: 'group',
          suggestionId: 'suggestion-two',
          placeName: 'Sunsuria Forum',
          placeId: 'places/sunsuria-forum',
          latitude: 3.12,
          longitude: 101.49,
          position: 1,
          estimatedDurationMinutes: 0,
          travelTimeFromPreviousMinutes: 4,
          status: StopStatus.completed,
        ),
      ];

      final anchor = recommendationAnchorFor(group, stops);

      expect(anchor?.name, 'Sunsuria Forum');
      expect(anchor?.id, 'places/sunsuria-forum');
      expect(anchor?.latitude, 3.12);
    },
  );
}
