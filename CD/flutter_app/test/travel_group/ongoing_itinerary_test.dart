import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/travel_group/features/travel_group/controllers/travel_group_controller.dart';
import 'package:flutter_app/travel_group/features/travel_group/models/travel_group_models.dart';
import 'package:flutter_app/travel_group/features/travel_group/repositories/mock_travel_group_repository.dart';
import 'package:flutter_app/travel_group/features/travel_group/services/member_location_clusters.dart';
import 'package:flutter_app/travel_group/features/travel_group/services/live_trip_location_service.dart';

void main() {
  test(
    'a stale Start next button cannot navigate to another destination',
    () async {
      final repo = MockTravelGroupRepository.seeded();
      await repo.confirmSuggestion('SUGGESTION_002');
      await repo.confirmSuggestion('SUGGESTION_003');
      await repo.startItinerary('GROUP_001');
      final stops = await repo.getItinerary('GROUP_001');
      await repo.markStopCompleted(
        groupId: 'GROUP_001',
        stopId: stops.first.id,
      );
      await expectLater(
        repo.startItinerary('GROUP_001', expectedStopId: stops[2].id),
        throwsA(isA<TravelGroupException>()),
      );
      expect(
        (await repo.getItinerary(
          'GROUP_001',
        )).where((s) => s.status == StopStatus.current),
        isEmpty,
      );
      await repo.startItinerary('GROUP_001', expectedStopId: stops[1].id);
      expect(
        (await repo.getItinerary(
          'GROUP_001',
        )).firstWhere((s) => s.status == StopStatus.current).id,
        stops[1].id,
      );
    },
  );
  test(
    'removing a suggestion preserves its completed itinerary snapshot',
    () async {
      final repo = MockTravelGroupRepository.seeded();
      await repo.confirmSuggestion('SUGGESTION_002');
      await repo.startItinerary('GROUP_001');
      var stops = await repo.getItinerary('GROUP_001');
      await repo.markStopCompleted(
        groupId: 'GROUP_001',
        stopId: stops.first.id,
      );
      await repo.startItinerary('GROUP_001');
      stops = await repo.getItinerary('GROUP_001');
      final confirmed = stops.firstWhere(
        (s) => s.suggestionId == 'SUGGESTION_002',
      );
      await repo.markStopCompleted(groupId: 'GROUP_001', stopId: confirmed.id);
      await repo.removeSuggestion('SUGGESTION_002');
      expect(
        (await repo.getItinerary('GROUP_001')).map((s) => s.id),
        contains(confirmed.id),
      );
    },
  );
  test(
    'creator can reorder future stops during travel, and next leg follows the new order',
    () async {
      final controller = TravelGroupController(
        repository: MockTravelGroupRepository.seeded(),
      );
      await controller.openGroup('GROUP_001');
      await controller.confirmSuggestion(
        controller.suggestions.firstWhere((s) => s.id == 'SUGGESTION_002'),
      );
      await controller.confirmSuggestion(
        controller.suggestions.firstWhere((s) => s.id == 'SUGGESTION_003'),
      );
      final first = controller.itinerary.first.id;
      final next = controller.itinerary[2].id;
      await controller.startItinerary();
      await controller.reorderStops(1, 2);
      expect(controller.itinerary.first.id, first);
      expect(controller.itinerary.first.status, StopStatus.current);
      expect(controller.itinerary[1].id, next);
      await expectLater(
        controller.reorderStops(0, 1),
        throwsA(isA<TravelGroupException>()),
      );
      await controller.completeStop(controller.itinerary.first);
      await controller.startItinerary();
      expect(controller.itinerary.first.status, StopStatus.completed);
      expect(
        controller.itinerary
            .firstWhere((s) => s.status == StopStatus.current)
            .id,
        next,
      );
      controller.dispose();
    },
  );
  test(
    'overlapping live members become a counted stack without moving coordinates',
    () {
      LiveMemberLocation member(String id, double lat, DateTime time) =>
          LiveMemberLocation(
            userId: id,
            displayName: id,
            coordinate: GeoCoordinate(lat, 101.4),
            updatedAt: time,
            isCurrentUser: false,
          );
      final now = DateTime.now();
      final members = [
        member('a', 3.1, now),
        member('b', 3.1, now),
        member('c', 3.2, now),
        member('stale', 3.1, now.subtract(const Duration(minutes: 3))),
      ];
      final clusters = clusterMemberLocations(members);
      expect(clusters.map((c) => c.length), [2, 1]);
      expect(members[1].coordinate.latitude, 3.1);
    },
  );
  test(
    'confirming another suggestion while visiting must not start navigation',
    () async {
      final repository = MockTravelGroupRepository.seeded();
      await repository.startItinerary('GROUP_001');
      final first = (await repository.getItinerary('GROUP_001')).first;
      await repository.markStopCompleted(
        groupId: 'GROUP_001',
        stopId: first.id,
      );
      await repository.confirmSuggestion('SUGGESTION_002');
      expect(
        (await repository.getGroup('GROUP_001'))!.tripPhase,
        GroupTripPhase.choosingNext,
      );
      expect(
        (await repository.getItinerary(
          'GROUP_001',
        )).where((stop) => stop.status == StopStatus.current),
        isEmpty,
      );
      await repository.startItinerary('GROUP_001');
      expect(
        (await repository.getItinerary('GROUP_001')).first.status,
        StopStatus.completed,
      );
      expect(
        (await repository.getItinerary(
          'GROUP_001',
        )).where((stop) => stop.status == StopStatus.current).length,
        1,
      );
    },
  );
}
