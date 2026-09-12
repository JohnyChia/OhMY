import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/travel_group/features/travel_group/controllers/travel_group_controller.dart';
import 'package:flutter_app/travel_group/features/travel_group/models/travel_group_models.dart';
import 'package:flutter_app/travel_group/features/travel_group/repositories/mock_travel_group_repository.dart';
import 'package:flutter_app/travel_group/features/travel_group/services/live_trip_location_service.dart';
import 'package:flutter_app/travel_group/features/travel_group/utils/profanity_filter.dart';

void main() {
  group('ProfanityFilter', () {
    test('blocks profanity across supported languages', () {
      expect(ProfanityFilter.hasProfanity('Sunset Fuck Walk'), isTrue);
      expect(ProfanityFilter.hasProfanity('Jalan Pukimak Food Tour'), isTrue);
      expect(ProfanityFilter.hasProfanity('操你妈美食团'), isTrue);
      expect(ProfanityFilter.hasProfanity('ஒத்த trip crew'), isTrue);
      expect(ProfanityFilter.hasProfanity('otha walking group'), isTrue);
    });

    test('normalizes leet speak and repeated letters', () {
      expect(ProfanityFilter.hasProfanity('F u c k i n g the Police'), isTrue);
      expect(ProfanityFilter.hasProfanity('fuuuuck sunset walk'), isTrue);
      expect(ProfanityFilter.hasProfanity('sh1t happens'), isTrue);
      expect(ProfanityFilter.hasProfanity('puk1mak tour'), isTrue);
    });

    test('allows normal travel text including lookalike words', () {
      expect(ProfanityFilter.hasProfanity('Sunset Photography Walk'), isFalse);
      expect(
        ProfanityFilter.hasProfanity('Walk as a group around KL'),
        isFalse,
      );
      expect(ProfanityFilter.hasProfanity('Assam Laksa Food Crawl'), isFalse);
      expect(ProfanityFilter.hasProfanity('Classic Heritage Tour'), isFalse);
      expect(ProfanityFilter.hasProfanity('Batu Caves Quick Visit'), isFalse);
      expect(
        ProfanityFilter.hasProfanity('Petaling Street Food Hunt'),
        isFalse,
      );
      expect(ProfanityFilter.hasProfanity('Up to 4 travellers total'), isFalse);
    });
  });

  group('TravelGroupController group rules', () {
    late MockTravelGroupRepository repository;
    late TravelGroupController controller;

    setUp(() {
      repository = MockTravelGroupRepository.seeded();
      controller = TravelGroupController(repository: repository);
    });

    test('createGroup rejects profanity in title and description', () async {
      await expectLater(
        controller.createGroup(
          name: 'Pukimak Food Tour',
          destination: _place(),
          description: 'Nice trip',
          tags: const ['Food'],
          maxMembers: 4,
          joinMode: JoinMode.open,
        ),
        throwsA(
          isA<TravelGroupException>().having(
            (error) => error.code,
            'code',
            'profanity',
          ),
        ),
      );
      await expectLater(
        controller.createGroup(
          name: 'Nice trip',
          destination: _place(),
          description: 'This is shit fun',
          tags: const ['Food'],
          maxMembers: 4,
          joinMode: JoinMode.open,
        ),
        throwsA(
          isA<TravelGroupException>().having(
            (error) => error.code,
            'code',
            'profanity',
          ),
        ),
      );
    });

    test('createGroup enforces the 2 to 4 traveller capacity', () async {
      for (final invalid in [1, 5, 8]) {
        await expectLater(
          controller.createGroup(
            name: 'Sunset Walk',
            destination: _place(),
            description: 'Nice trip',
            tags: const ['Food'],
            maxMembers: invalid,
            joinMode: JoinMode.open,
          ),
          throwsA(
            isA<TravelGroupException>().having(
              (error) => error.code,
              'code',
              'invalid_capacity',
            ),
          ),
        );
      }
    });

    test(
      'creator edits title, capacity and join mode without losing members',
      () async {
        await controller.openGroup('GROUP_001');
        final memberCount = controller.activeGroup!.memberIds.length;

        await controller.editGroup(
          name: 'Petaling Street Night Hunt',
          description: 'Updated heritage streets tour.',
          maxMembers: 4,
          joinMode: JoinMode.request,
        );

        final group = controller.activeGroup!;
        expect(group.name, 'Petaling Street Night Hunt');
        expect(group.maxMembers, 4);
        expect(group.joinMode, JoinMode.request);
        expect(group.memberIds.length, memberCount);
      },
    );

    test(
      'edit cannot shrink capacity below the current member count',
      () async {
        await controller.openGroup('GROUP_001');
        expect(controller.activeGroup!.memberIds.length, 3);

        await expectLater(
          controller.editGroup(
            name: 'Petaling Street Food Hunt',
            description: 'Try to shrink the group.',
            maxMembers: 2,
            joinMode: JoinMode.open,
          ),
          throwsA(
            isA<TravelGroupException>().having(
              (error) => error.code,
              'code',
              'capacity_below_members',
            ),
          ),
        );
      },
    );

    test('edit is locked once the trip is active', () async {
      await controller.openGroup('GROUP_001');
      await controller.confirmSuggestion(
        controller.suggestions.firstWhere(
          (suggestion) => !suggestion.isConfirmed,
        ),
      );
      await controller.startItinerary();

      await expectLater(
        controller.editGroup(
          name: 'Petaling Street Food Hunt',
          description: 'Try to edit mid trip.',
          maxMembers: 4,
          joinMode: JoinMode.open,
        ),
        throwsA(
          isA<TravelGroupException>().having(
            (error) => error.code,
            'code',
            'edit_locked',
          ),
        ),
      );
    });

    test('a solo creator shows as 1 of 4 after creating a group', () async {
      final group = await controller.createGroup(
        name: 'KLCC Evening Stroll',
        destination: _place(),
        description: 'A relaxed evening walk.',
        tags: const ['Nature'],
        maxMembers: 4,
        joinMode: JoinMode.open,
      );
      expect(group.memberIds.length, 1);
      expect(group.maxMembers, 4);
      expect(group.memberIds.length, lessThan(group.maxMembers));
    });

    test('creator can own only one ongoing group at a time', () async {
      final emptyRepository = MockTravelGroupRepository(
        groups: [],
        requests: [],
        suggestions: [],
        itinerary: [],
      );
      final singleGroupController = TravelGroupController(
        repository: emptyRepository,
      );
      await singleGroupController.createGroup(
        name: 'KLCC Evening Stroll',
        destination: _place(),
        description: 'A relaxed evening walk.',
        tags: const ['Nature'],
        maxMembers: 4,
        joinMode: JoinMode.open,
      );

      await expectLater(
        singleGroupController.createGroup(
          name: 'Another Group',
          destination: _ampangPlace(),
          description: 'This must wait until the first group ends.',
          tags: const ['Heritage'],
          maxMembers: 4,
          joinMode: JoinMode.open,
        ),
        throwsA(
          isA<TravelGroupException>().having(
            (error) => error.code,
            'code',
            'ongoing_group_exists',
          ),
        ),
      );

      await singleGroupController.endTrip();
      expect(singleGroupController.hasOngoingCreatedGroup, isFalse);

      final nextGroup = await singleGroupController.createGroup(
        name: 'Another Group',
        destination: _ampangPlace(),
        description: 'This can start after the first group ends.',
        tags: const ['Heritage'],
        maxMembers: 4,
        joinMode: JoinMode.open,
      );
      expect(nextGroup.name, 'Another Group');
    });

    test('createGroup follows the repository-assigned group id', () async {
      final remoteRepository = _RemoteIdRepository();
      final remoteController = TravelGroupController(
        repository: remoteRepository,
      );

      final group = await remoteController.createGroup(
        name: 'Ampang Gang',
        destination: _ampangPlace(),
        description: 'A hike around Ampang.',
        tags: const ['Nature'],
        maxMembers: 4,
        joinMode: JoinMode.open,
      );

      expect(group.id, 'REMOTE_GROUP_ID');
      expect(remoteController.activeGroup?.id, 'REMOTE_GROUP_ID');
    });

    test('only the creator can delete a group', () async {
      await controller.openGroup('GROUP_001');
      await controller.deleteActiveGroup();
      expect(await repository.getGroup('GROUP_001'), isNull);
      expect(controller.activeGroup, isNull);

      await controller.openGroup('GROUP_002');
      await expectLater(
        controller.deleteActiveGroup(),
        throwsA(
          isA<TravelGroupException>().having(
            (error) => error.code,
            'code',
            'creator_only',
          ),
        ),
      );
    });

    test('only travellers within 10 km of the destination can join', () async {
      await controller.openGroup('GROUP_002');

      await expectLater(
        controller.joinActiveGroup(
          location: const GeoCoordinate(3.1094685, 101.4602178),
        ),
        throwsA(
          isA<TravelGroupException>().having(
            (error) => error.code,
            'code',
            'outside_destination_radius',
          ),
        ),
      );

      await controller.joinActiveGroup(
        location: const GeoCoordinate(3.1580, 101.7120),
      );
      expect(controller.isMember, isTrue);
    });

    test('a creator cannot join another ongoing group', () async {
      await controller.restoreOngoingCreatedGroup();
      await controller.openGroup('GROUP_002');

      await expectLater(
        controller.joinActiveGroup(
          location: const GeoCoordinate(3.1580, 101.7120),
        ),
        throwsA(
          isA<TravelGroupException>().having(
            (error) => error.code,
            'code',
            'creator_already_in_group',
          ),
        ),
      );
    });

    test('the first destination cannot be suggested again', () async {
      await controller.createGroup(
        name: 'KLCC Evening Stroll',
        destination: _place(),
        description: 'A relaxed evening walk.',
        tags: const ['Nature'],
        maxMembers: 4,
        joinMode: JoinMode.open,
      );

      await expectLater(
        controller.addSuggestion(
          NearbyPlace(
            name: _place().name,
            source: 'Google Places',
            category: 'Attraction',
            distanceKm: 0,
            crowdLevel: 'Unknown',
            durationMinutes: 60,
            tags: const ['Nature'],
            placeId: _place().id,
            latitude: _place().latitude,
            longitude: _place().longitude,
          ),
        ),
        throwsA(
          isA<TravelGroupException>().having(
            (error) => error.code,
            'code',
            'duplicate_place',
          ),
        ),
      );
    });

    test(
      'reorder recalculates legs and itinerary stops can be removed',
      () async {
        await controller.createGroup(
          name: 'KL City Loop',
          destination: _place(),
          description: 'Plan as we travel.',
          tags: const ['Culture'],
          maxMembers: 4,
          joinMode: JoinMode.open,
        );
        await controller.setMeetupPoint(
          name: 'Meet here',
          latitude: 3.1500,
          longitude: 101.7100,
          members: [
            LiveMemberLocation(
              userId: controller.currentUser.id,
              displayName: controller.currentUser.name,
              coordinate: const GeoCoordinate(3.1500, 101.7100),
              updatedAt: DateTime.now(),
              isCurrentUser: true,
            ),
          ],
        );
        await controller.addSuggestion(
          const NearbyPlace(
            name: 'Central Market',
            source: 'Google Places',
            category: 'Culture',
            distanceKm: 2,
            crowdLevel: 'Moderate',
            durationMinutes: 60,
            tags: ['Culture'],
            placeId: 'places/central-market',
            latitude: 3.1457,
            longitude: 101.6953,
          ),
        );
        await controller.addSuggestion(
          const NearbyPlace(
            name: 'Merdeka Square',
            source: 'Google Places',
            category: 'Heritage',
            distanceKm: 2.4,
            crowdLevel: 'Moderate',
            durationMinutes: 45,
            tags: ['Heritage'],
            placeId: 'places/merdeka-square',
            latitude: 3.1478,
            longitude: 101.6937,
          ),
        );
        await controller.confirmSuggestion(
          controller.suggestions.firstWhere(
            (suggestion) => suggestion.placeName == 'Central Market',
          ),
        );
        await controller.confirmSuggestion(
          controller.suggestions.firstWhere(
            (suggestion) => suggestion.placeName == 'Merdeka Square',
          ),
        );

        await controller.reorderStops(2, 1);
        expect(controller.itinerary.first.placeName, _place().name);
        expect(controller.itinerary[1].placeName, 'Merdeka Square');
        expect(
          controller.itinerary[1].travelDistanceFromPreviousKm,
          greaterThan(0),
        );
        expect(
          controller.itinerary[1].travelTimeFromPreviousMinutes,
          greaterThan(0),
        );

        final removable = controller.itinerary[1];
        await controller.removeStop(removable);
        expect(
          controller.itinerary.any((stop) => stop.id == removable.id),
          isFalse,
        );
        expect(
          controller.suggestions
              .firstWhere((item) => item.id == removable.suggestionId)
              .isConfirmed,
          isFalse,
        );
      },
    );

    test('a group trip needs at least two joined travellers', () async {
      await controller.createGroup(
        name: 'KL City Loop',
        destination: _place(),
        description: 'Plan as we travel.',
        tags: const ['Culture'],
        maxMembers: 4,
        joinMode: JoinMode.open,
      );
      await expectLater(
        controller.startItinerary(),
        throwsA(
          isA<TravelGroupException>().having(
            (error) => error.code,
            'code',
            'not_enough_members',
          ),
        ),
      );
    });
  });

  group('MockTravelGroupRepository.updateGroup', () {
    test('rejects capacity below the current member count', () async {
      final repository = MockTravelGroupRepository.seeded();
      final group = (await repository.getGroup('GROUP_004'))!;
      group.maxMembers = 2;
      await expectLater(
        repository.updateGroup(group),
        throwsA(
          isA<TravelGroupException>().having(
            (error) => error.code,
            'code',
            'capacity_below_members',
          ),
        ),
      );
    });

    test('rejects capacities outside 2 to 4', () async {
      final repository = MockTravelGroupRepository.seeded();
      final group = (await repository.getGroup('GROUP_002'))!;
      group.maxMembers = 8;
      await expectLater(
        repository.updateGroup(group),
        throwsA(
          isA<TravelGroupException>().having(
            (error) => error.code,
            'code',
            'invalid_capacity',
          ),
        ),
      );
    });

    test('updates editable fields and keeps members', () async {
      final repository = MockTravelGroupRepository.seeded();
      final group = (await repository.getGroup('GROUP_002'))!;
      final members = List<String>.from(group.memberIds);
      group
        ..name = 'KLCC Night Loop'
        ..description = 'Updated.'
        ..maxMembers = 3
        ..joinMode = JoinMode.request
        ..destination = 'KLCC Park Fountain'
        ..destinationLatitude = 3.1577
        ..destinationLongitude = 101.7119;

      await repository.updateGroup(group);

      final updated = (await repository.getGroup('GROUP_002'))!;
      expect(updated.name, 'KLCC Night Loop');
      expect(updated.maxMembers, 3);
      expect(updated.joinMode, JoinMode.request);
      expect(updated.destination, 'KLCC Park Fountain');
      expect(updated.memberIds, members);
    });
  });
}

TravelGroupPlace _place() => const TravelGroupPlace(
  id: 'places/klcc',
  name: 'KLCC Park',
  address: 'Kuala Lumpur City Centre, Kuala Lumpur',
  latitude: 3.1532,
  longitude: 101.7149,
);

TravelGroupPlace _ampangPlace() => const TravelGroupPlace(
  id: 'places/saga-hill',
  name: 'Saga Hill',
  address: 'Taman Saga, 68000 Ampang, Selangor',
  latitude: 3.1096205,
  longitude: 101.7790292,
);

class _RemoteIdRepository extends MockTravelGroupRepository {
  _RemoteIdRepository()
    : super(groups: [], requests: [], suggestions: [], itinerary: []);

  @override
  Future<TravelGroup> createGroup(TravelGroup group) {
    return super.createGroup(
      TravelGroup(
        id: 'REMOTE_GROUP_ID',
        creatorId: group.creatorId,
        creatorName: group.creatorName,
        name: group.name,
        destination: group.destination,
        description: group.description,
        meetupPoint: group.meetupPoint,
        tags: List<String>.from(group.tags),
        maxMembers: group.maxMembers,
        distanceKm: group.distanceKm,
        joinMode: group.joinMode,
        status: group.status,
        memberIds: List<String>.from(group.memberIds),
        destinationPlaceId: group.destinationPlaceId,
        destinationAddress: group.destinationAddress,
        destinationLatitude: group.destinationLatitude,
        destinationLongitude: group.destinationLongitude,
        destinationPhotoName: group.destinationPhotoName,
      ),
    );
  }
}
