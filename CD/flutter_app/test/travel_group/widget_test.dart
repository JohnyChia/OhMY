import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/travel_group/features/travel_group/controllers/travel_group_controller.dart';
import 'package:flutter_app/travel_group/features/travel_group/models/travel_group_models.dart';
import 'package:flutter_app/travel_group/features/travel_group/repositories/mock_travel_group_repository.dart';
import 'package:flutter_app/travel_group/features/travel_group/screens/travel_group_discovery_screen.dart';
import 'package:flutter_app/travel_group/features/travel_group/screens/group_lobby_screen.dart';
import 'package:flutter_app/travel_group/features/travel_group/services/live_trip_location_service.dart';
import 'package:flutter_app/travel_group/features/travel_group/services/travel_place_search_service.dart';

void main() {
  late MockTravelGroupRepository repository;
  late TravelGroupController controller;
  late _FakePlaceSearchService placeSearch;

  setUp(() {
    repository = MockTravelGroupRepository.seeded();
    controller = TravelGroupController(repository: repository);
    placeSearch = _FakePlaceSearchService();
  });

  Widget app() => MaterialApp(
    home: TravelGroupDiscoveryScreen(
      controller: controller,
      placeSearchService: placeSearch,
    ),
  );

  testWidgets('discovery is destination-led and uses a right-side create FAB', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Travel Groups'), findsOneWidget);
    expect(find.text('Petaling Street'), findsOneWidget);
    expect(find.text('Petaling Street Food Hunt'), findsOneWidget);
    expect(find.textContaining('km away'), findsNothing);
    expect(find.textContaining('within 10 km'), findsOneWidget);
    expect(find.textContaining('Verified'), findsNothing);
    expect(find.byKey(const Key('create_group_fab')), findsOneWidget);
  });

  testWidgets('area control opens an area dropdown', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('area_dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('Subang Jaya'), findsOneWidget);
  });

  testWidgets('creation requires selecting a searched destination', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create_group_fab')));
    await tester.pumpAndSettle();

    expect(find.text('Meetup point'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('group_title')),
      'KL Sunset Walk',
    );
    await tester.enterText(find.byKey(const Key('destination_search')), 'KLCC');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('destination_result_0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('group_description')),
      'A relaxed evening walk around the city centre.',
    );
    await tester.tap(find.text('Food').last);
    await tester.scrollUntilVisible(
      find.text('Create group'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Create group'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(controller.activeGroup?.name, 'KL Sunset Walk');
    expect(controller.activeGroup?.destination, 'KLCC Park');
    expect(controller.activeGroup?.meetupPoint, isEmpty);
    expect(find.text('KL Sunset Walk'), findsWidgets);
    expect(find.text('1 of 4 members'), findsOneWidget);
    expect(find.text('Create Travel Group'), findsNothing);
    expect(find.text('Group successfully created'), findsOneWidget);
  });

  testWidgets('suggestion cards fit a phone viewport without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await controller.openGroup('GROUP_001');
    await tester.pumpWidget(
      MaterialApp(home: GroupLobbyScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suggestions').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Member suggestions'), findsOneWidget);
  });

  testWidgets(
    'lobby lists members, opens profiles, and has no progress panel',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 812));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await controller.openGroup('GROUP_001');
      await tester.pumpWidget(
        MaterialApp(home: GroupLobbyScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Planning Progress'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('member_profile_USER_101')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('member_profile_USER_101')), findsOneWidget);

      tester
          .widget<InkWell>(find.byKey(const Key('member_profile_USER_101')))
          .onTap!();
      await tester.pumpAndSettle();

      expect(find.text('Traveller profile'), findsOneWidget);
      expect(find.text('Farah Imani'), findsOneWidget);
      expect(find.text('Travel preferences'), findsOneWidget);
      expect(find.text('Heritage'), findsOneWidget);
    },
  );

  testWidgets('deleting the displayed group does not rebuild a null lobby', (
    tester,
  ) async {
    await controller.openGroup('GROUP_001');
    await tester.pumpWidget(
      MaterialApp(home: GroupLobbyScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('group_actions_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete group'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_delete_group_button')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(controller.activeGroup, isNull);
  });

  test('creator meetup must be within 5 km of every live member', () async {
    await controller.openGroup('GROUP_001');
    final members = [
      LiveMemberLocation(
        userId: 'USER_100',
        displayName: 'Aina Sofea',
        coordinate: const GeoCoordinate(3.145, 101.695),
        updatedAt: DateTime.now(),
        isCurrentUser: true,
      ),
      LiveMemberLocation(
        userId: 'USER_101',
        displayName: 'Farah',
        coordinate: const GeoCoordinate(3.150, 101.700),
        updatedAt: DateTime.now(),
        isCurrentUser: false,
      ),
    ];

    await controller.setMeetupPoint(
      name: 'Central Market entrance',
      latitude: 3.147,
      longitude: 101.697,
      members: members,
    );
    expect(controller.activeGroup?.meetupPoint, 'Central Market entrance');

    await expectLater(
      controller.setMeetupPoint(
        name: 'Too far',
        latitude: 3.250,
        longitude: 101.800,
        members: members,
      ),
      throwsA(
        isA<TravelGroupException>().having(
          (error) => error.code,
          'code',
          'meetup_out_of_range',
        ),
      ),
    );
  });
}

class _FakePlaceSearchService extends TravelPlaceSearchService {
  @override
  Future<List<TravelGroupPlace>> search(
    String query, {
    bool placesOnly = true,
  }) async => const [
    TravelGroupPlace(
      id: 'places/klcc',
      name: 'KLCC Park',
      address: 'Kuala Lumpur City Centre, Kuala Lumpur',
      latitude: 3.1532,
      longitude: 101.7149,
    ),
  ];

  @override
  Future<TravelGroupPlace> loadDetails(TravelGroupPlace place) async => place;

  @override
  void dispose() {}
}
