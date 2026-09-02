import 'package:flutter_test/flutter_test.dart';
import 'package:travel_group_prototype/features/travel_group/models/travel_group_models.dart';
import 'package:travel_group_prototype/features/travel_group/repositories/mock_travel_group_repository.dart';
import 'package:travel_group_prototype/features/travel_group/services/live_trip_location_service.dart';
import 'package:travel_group_prototype/features/travel_group/services/travel_map_service.dart';

void main() {
  group('MockTravelGroupRepository', () {
    test('filters nearby groups and joins an open group once', () async {
      final repository = MockTravelGroupRepository.seeded();
      final nearby = await repository.getNearbyGroups(radiusKm: 2);
      expect(nearby.map((group) => group.id), ['GROUP_001', 'GROUP_002']);

      await repository.joinOpenGroup(
          groupId: 'GROUP_002', travellerId: 'USER_TEST');
      await repository.joinOpenGroup(
          groupId: 'GROUP_002', travellerId: 'USER_TEST');
      final group = await repository.getGroup('GROUP_002');
      expect(group!.memberIds.where((id) => id == 'USER_TEST').length, 1);
    });

    test('request joining prevents duplicate pending requests', () async {
      final repository = MockTravelGroupRepository.seeded();
      final user = PrototypeUser(
          id: 'USER_TEST', name: 'Test Traveller', isVerified: true);
      final first =
          await repository.requestToJoin(groupId: 'GROUP_003', traveller: user);
      final second =
          await repository.requestToJoin(groupId: 'GROUP_003', traveller: user);
      expect(second.id, first.id);
    });

    test('switching a vote removes the opposite vote', () async {
      final repository = MockTravelGroupRepository.seeded();
      await repository.voteSuggestion(
          suggestionId: 'SUGGESTION_002', userId: 'USER_100', isUpvote: true);
      await repository.voteSuggestion(
          suggestionId: 'SUGGESTION_002', userId: 'USER_100', isUpvote: false);
      final suggestion = (await repository.getSuggestions('GROUP_001'))
          .firstWhere((item) => item.id == 'SUGGESTION_002');
      expect(suggestion.upvoterIds.contains('USER_100'), isFalse);
      expect(suggestion.downvoterIds.contains('USER_100'), isTrue);
    });

    test('completing a stop advances the next stop', () async {
      final repository = MockTravelGroupRepository.seeded();
      await repository.confirmSuggestion('SUGGESTION_002');
      await repository.startItinerary('GROUP_001');
      var itinerary = await repository.getItinerary('GROUP_001');
      expect(itinerary.map((stop) => stop.status),
          [StopStatus.current, StopStatus.upcoming]);

      await repository.markStopCompleted(
          groupId: 'GROUP_001', stopId: itinerary.first.id);
      itinerary = await repository.getItinerary('GROUP_001');
      expect(itinerary.map((stop) => stop.status),
          [StopStatus.completed, StopStatus.current]);
    });
  });

  test('mock map advances position while ETA decreases', () {
    final service = MockTravelMapService();
    final start = service.snapshot(0);
    final later = service.snapshot(.7);
    expect(later.position, isNot(start.position));
    expect(later.etaMinutes, lessThan(start.etaMinutes));
    expect(later.distanceKm, lessThan(start.distanceKm));
  });

  test('live trip service publishes the signed-in member location', () async {
    final repository = MockTravelGroupRepository.seeded();
    final group = (await repository.getGroup('GROUP_001'))!;
    final currentUser = PrototypeUser(
      id: 'USER_100',
      name: 'Aina Sofea',
      isVerified: true,
    );
    final service = MockLiveTripLocationService(
      group: group,
      currentUser: currentUser,
    );

    final first = await service.watchLocations().first;
    expect(first.length, group.memberIds.length);

    final updatedFuture = service.watchLocations().skip(1).first;
    await Future<void>.delayed(Duration.zero);
    service.publishOwnLocation(
      latitude: 3.139,
      longitude: 101.6869,
      accuracyMeters: 5,
    );
    final updated = await updatedFuture;
    final ownLocation = updated.firstWhere((member) => member.isCurrentUser);
    expect(ownLocation.coordinate.latitude, 3.139);
    expect(ownLocation.coordinate.longitude, 101.6869);
    expect(ownLocation.accuracyMeters, 5);

    await service.dispose();
  });
}
