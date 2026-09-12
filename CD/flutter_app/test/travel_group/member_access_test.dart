import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/travel_group/features/travel_group/controllers/travel_group_controller.dart';
import 'package:flutter_app/travel_group/features/travel_group/repositories/mock_travel_group_repository.dart';
import 'package:flutter_app/travel_group/features/travel_group/models/travel_group_models.dart';
import 'package:flutter_app/travel_group/features/travel_group/services/live_trip_location_service.dart';

void main() {
  test('creator cannot confirm a group while still alone', () async {
    final repository = MockTravelGroupRepository.seeded();
    final controller = TravelGroupController(repository: repository);
    await controller.openGroup('GROUP_001');
    final group = controller.activeGroup!;
    group.memberIds
      ..clear()
      ..add(group.creatorId);
    group.memberCount = 1;

    await expectLater(
      controller.confirmGroup(),
      throwsA(
        isA<TravelGroupException>()
            .having((error) => error.code, 'code', 'not_enough_members')
            .having(
              (error) => error.message,
              'message',
              contains('another traveller'),
            ),
      ),
    );
    expect(group.isConfirmed, isFalse);
    expect(await repository.getActiveTripSession(group.id), isNull);
    controller.dispose();
  });

  test(
    'joined traveller is blocked from solo until group is finished',
    () async {
      final controller = TravelGroupController(
        repository: MockTravelGroupRepository.seeded(),
      );
      await controller.loadGroups();
      final group = controller.groups.first;
      controller.switchUser(
        PrototypeUser(
          id: group.memberIds.firstWhere((id) => id != group.creatorId),
          name: 'Member',
          isVerified: true,
        ),
      );
      await controller.openGroup(group.id);
      expect(controller.ongoingMemberGroup, isNotNull);
      group.status = GroupStatus.completed;
      expect(controller.ongoingMemberGroup, isNull);
      controller.dispose();
    },
  );
  test('membership is restored even without opening a lobby', () async {
    final controller = TravelGroupController(
      repository: MockTravelGroupRepository.seeded(),
      currentUser: PrototypeUser(
        id: 'USER_101',
        name: 'Traveller',
        isVerified: true,
      ),
    );
    await controller.restoreOngoingCreatedGroup();
    expect(controller.ongoingMemberGroup, isNotNull);
    expect(controller.isMember, isTrue);
    controller.dispose();
  });
  test('creation checks destination distance, not browsing area', () {
    final controller = TravelGroupController(
      repository: MockTravelGroupRepository.seeded(),
    );
    const place = TravelGroupPlace(
      id: 'mall',
      name: 'Mall',
      address: 'Setia Alam',
      latitude: 3.11,
      longitude: 101.46,
    );
    expect(
      () => controller.validateCreatorLocation(
        place,
        const GeoCoordinate(3.11, 101.46),
      ),
      returnsNormally,
    );
    expect(
      () => controller.validateCreatorLocation(
        place,
        const GeoCoordinate(3.16, 101.71),
      ),
      throwsA(isA<TravelGroupException>()),
    );
    controller.dispose();
  });
}
