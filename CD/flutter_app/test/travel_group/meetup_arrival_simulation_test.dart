import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/travel_group/features/travel_group/controllers/travel_group_controller.dart';
import 'package:flutter_app/travel_group/features/travel_group/repositories/mock_travel_group_repository.dart';
import 'package:flutter_app/travel_group/features/travel_group/services/live_trip_location_service.dart';
import 'package:flutter_app/travel_group/features/travel_group/services/meetup_arrival_simulation.dart';

void main() {
  test(
    'controller simulation publishes while both lobby and map GPS are suppressed',
    () async {
      final delegate = _RecordingService();
      final controller = TravelGroupController(
        repository: MockTravelGroupRepository.seeded(),
        liveTripLocationServiceFactory:
            ({required group, required currentUser, required sessionId}) =>
                delegate,
      );
      await controller.openGroup('GROUP_001');
      await controller.confirmGroup();
      controller.activeGroup!
        ..meetupLatitude = 3.11
        ..meetupLongitude = 101.41;
      final lobby = controller.createLiveTripLocationService();
      final map = controller.createLiveTripLocationService();
      await controller.simulateToMeetup(const GeoCoordinate(3.10, 101.40));
      expect(delegate.writes, 1);
      await lobby.publishOwnLocation(latitude: 0, longitude: 0);
      await map.publishOwnLocation(latitude: 0, longitude: 0);
      expect(delegate.writes, 1);
      for (var i = 0; i < 20; i++) {
        await controller.meetupSimulation!.advance();
      }
      expect(controller.meetupSimulation!.arrived, isTrue);
      expect(delegate.writes, 21);
      controller.stopMeetupSimulation();
      await lobby.publishOwnLocation(latitude: 0, longitude: 0);
      expect(delegate.writes, 22);
      controller.dispose();
    },
  );
  test(
    'moves gradually, reaches meetup and refreshes arrival without teleporting',
    () async {
      final locations = <GeoCoordinate>[];
      final simulation = MeetupArrivalSimulation(
        start: const GeoCoordinate(3.10, 101.40),
        target: const GeoCoordinate(3.11, 101.41),
        publish: (coordinate) async {
          locations.add(coordinate);
        },
        onUpdate: () {},
        onError: (error) => fail('$error'),
      );
      expect(simulation.coordinate.latitude, 3.10);
      await simulation.advance();
      expect(simulation.coordinate.latitude, greaterThan(3.10));
      expect(simulation.coordinate.latitude, lessThan(3.11));
      for (var i = 1; i < 20; i++) {
        await simulation.advance();
      }
      expect(simulation.arrived, isTrue);
      expect(simulation.coordinate.latitude, 3.11);
      await simulation.advance();
      expect(locations.length, 21);
      simulation.stop();
      await simulation.advance();
      expect(locations.length, 21);
    },
  );

  test('GPS writes are suppressed only while simulation is active', () async {
    final delegate = _RecordingService();
    var simulating = true;
    final service = SimulationAwareLocationService(delegate, () => simulating);
    await service.publishOwnLocation(latitude: 1, longitude: 2);
    expect(delegate.writes, 0);
    simulating = false;
    await service.publishOwnLocation(latitude: 1, longitude: 2);
    expect(delegate.writes, 1);
    await service.dispose();
  });
}

class _RecordingService implements LiveTripLocationService {
  int writes = 0;
  @override
  Future<void> publishOwnLocation({
    required double latitude,
    required double longitude,
    double? accuracyMeters,
  }) async {
    writes++;
  }

  @override
  Stream<List<LiveMemberLocation>> watchLocations() => const Stream.empty();
  @override
  Future<void> dispose() async {}
}
