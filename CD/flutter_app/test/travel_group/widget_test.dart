import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_app/travel_group/features/travel_group/controllers/travel_group_controller.dart';
import 'package:flutter_app/travel_group/features/travel_group/models/travel_group_models.dart';
import 'package:flutter_app/travel_group/features/travel_group/repositories/mock_travel_group_repository.dart';
import 'package:flutter_app/travel_group/features/travel_group/screens/travel_group_discovery_screen.dart';
import 'package:flutter_app/travel_group/features/travel_group/screens/group_lobby_screen.dart';
import 'package:flutter_app/travel_group/features/travel_group/screens/group_details_screen.dart';
import 'package:flutter_app/travel_group/features/travel_group/screens/itinerary_board.dart';
import 'package:flutter_app/travel_group/features/travel_group/services/live_trip_location_service.dart';
import 'package:flutter_app/travel_group/features/travel_group/services/travel_place_search_service.dart';

void main() {
  late MockTravelGroupRepository repository;
  late TravelGroupController controller;
  late _FakePlaceSearchService placeSearch;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          (call) async {
            switch (call.method) {
              case 'isLocationServiceEnabled':
                return true;
              case 'checkPermission':
              case 'requestPermission':
                return 2;
              case 'getCurrentPosition':
                return {
                  'latitude': 3.1579,
                  'longitude': 101.7123,
                  'accuracy': 5.0,
                  'altitude': 0.0,
                  'heading': 0.0,
                  'speed': 0.0,
                  'speed_accuracy': 0.0,
                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                };
              default:
                return null;
            }
          },
        );
    repository = MockTravelGroupRepository.seeded();
    controller = TravelGroupController(repository: repository);
    placeSearch = _FakePlaceSearchService();
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          null,
        );
  });

  Widget app() => MaterialApp(
    home: TravelGroupDiscoveryScreen(
      controller: controller,
      placeSearchService: placeSearch,
    ),
  );

  testWidgets(
    'creator cannot confirm from the lobby until another traveller joins',
    (tester) async {
      await controller.openGroup('GROUP_001');
      final group = controller.activeGroup!;
      group.memberIds
        ..clear()
        ..add(group.creatorId);
      group.memberCount = 1;
      await tester.pumpWidget(
        MaterialApp(home: GroupLobbyScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('confirm_group_button')),
      );
      expect(button.onPressed, isNull);
      expect(find.text('Waiting for another traveller'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'outsider group details never reveal the confirmed meetup point',
    (tester) async {
      controller.switchUser(
        PrototypeUser(
          id: 'USER_500',
          name: 'Outside traveller',
          isVerified: true,
        ),
      );
      await controller.openGroup('GROUP_001');
      controller.activeGroup!.confirmedAt = DateTime.now();
      final privateMeetup = controller.activeGroup!.meetupPoint;
      await tester.pumpWidget(
        MaterialApp(
          home: GroupDetailsScreen(
            controller: controller,
            placeSearchService: placeSearch,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(privateMeetup), findsNothing);
      expect(find.text('MEETUP POINT'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -420));
      await tester.pumpAndSettle();
      expect(find.text('FIRST DESTINATION'), findsOneWidget);
      expect(
        find.textContaining('Meetup and live locations stay private'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'long pressing the whole future card reorders it and visit placeholder is absent',
    (tester) async {
      await controller.openGroup('GROUP_001');
      await controller.confirmSuggestion(
        controller.suggestions.firstWhere((s) => s.id == 'SUGGESTION_002'),
      );
      await controller.confirmSuggestion(
        controller.suggestions.firstWhere((s) => s.id == 'SUGGESTION_003'),
      );
      await controller.startItinerary();
      await controller.completeStop(controller.itinerary.first);
      final initialId = controller.itinerary.first.id;
      final moving = controller.itinerary[1];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: controller,
              builder: (_, _) => ItineraryBoard(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('min visit'), findsNothing);
      expect(
        find.byType(ReorderableDelayedDragStartListener),
        findsNWidgets(2),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(ValueKey(moving.id))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, 230));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(controller.itinerary.first.id, initialId);
      expect(controller.itinerary[2].id, moving.id);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('traveller sees that the creator ended the shared session', (
    tester,
  ) async {
    await controller.openGroup('GROUP_001');
    final creator = controller.activeGroup!.creatorName;
    controller.switchUser(
      PrototypeUser(id: 'USER_101', name: 'Traveller', isVerified: true),
    );
    await tester.pumpWidget(
      MaterialApp(home: GroupLobbyScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    await repository.endTrip('GROUP_001');
    await controller.refreshWorkspace();
    await tester.pumpAndSettle();
    expect(
      find.text(
        '$creator ended this Travel Group session. Your trip history has been saved.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('area search only requests general urban areas', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('area_dropdown')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('area_search_field')), 'Shah');
    await tester.pumpAndSettle();

    expect(placeSearch.lastAreasOnly, isTrue);
  });

  testWidgets('submitting and selecting an area updates the discovery area', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('area_dropdown')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('area_search_field')),
      'Shah Alam',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('area_result_0')));
    await tester.pumpAndSettle();

    expect(controller.selectedArea, 'Shah Alam');
    expect(find.text('Choose your area'), findsNothing);
  });

  testWidgets('an empty area search shows a clear empty state', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('area_dropdown')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('area_search_field')),
      'zzzz nowhere',
    );
    await tester.pumpAndSettle();

    expect(find.text('No areas found'), findsOneWidget);
  });

  testWidgets('precise location resets browsing to the current general area', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await controller.setArea('Subang Jaya', latitude: 3.04, longitude: 101.58);

    await tester.tap(find.byKey(const Key('area_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('use_precise_area_button')));
    await tester.pumpAndSettle();

    expect(controller.selectedArea, 'Setia Alam');
    expect(controller.areaLatitude, 3.1579);
    expect(controller.areaLongitude, 101.7123);
    expect(find.text('Choose your area'), findsNothing);
  });

  testWidgets('creation requires selecting a searched destination', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create_group_fab')));
    await tester.pumpAndSettle();

    expect(find.text('Meetup point'), findsNothing);
    for (final tag in const [
      'Cultural Experience',
      'Cultural Festival',
      'Cultural Learning',
      'Heritage',
      'Historical Landmark',
      'Local Cuisine',
      'Religious Heritage',
      'Traditional Architecture',
      'Traditional Craft',
    ]) {
      expect(find.text(tag), findsOneWidget);
    }
    expect(find.text('Food'), findsNothing);
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
    await tester.tap(find.text('Cultural Experience').last);
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
    expect(find.text('Google Places'), findsNothing);
    expect(find.textContaining('Unknown crowd'), findsNothing);
    expect(find.textContaining('1 hr'), findsNothing);
  });

  testWidgets('workspace maps expose zoom controls and eager gestures', (
    tester,
  ) async {
    await controller.openGroup('GROUP_001');
    await tester.pumpWidget(
      MaterialApp(home: GroupLobbyScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    GoogleMap currentMap() => tester.widget<GoogleMap>(find.byType(GoogleMap));
    expect(currentMap().zoomControlsEnabled, isTrue);
    expect(currentMap().zoomGesturesEnabled, isTrue);
    expect(currentMap().scrollGesturesEnabled, isTrue);
    expect(currentMap().gestureRecognizers, isNotEmpty);

    await tester.tap(find.text('Suggestions').first);
    await tester.pumpAndSettle();
    expect(currentMap().zoomControlsEnabled, isTrue);
    expect(currentMap().gestureRecognizers, isNotEmpty);

    await tester.tap(find.text('Itinerary').first);
    await tester.pumpAndSettle();
    expect(currentMap().zoomControlsEnabled, isTrue);
    expect(currentMap().gestureRecognizers, isNotEmpty);
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
      expect(find.text('Trips completed'), findsOneWidget);
      expect(find.text('Community posts'), findsOneWidget);
      expect(
        find.byKey(const Key('remove_group_member_button')),
        findsOneWidget,
      );
    },
  );

  testWidgets('creator removes a traveller from their profile', (tester) async {
    await controller.openGroup('GROUP_001');
    await tester.pumpWidget(
      MaterialApp(home: GroupLobbyScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('member_profile_USER_101')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    tester
        .widget<InkWell>(find.byKey(const Key('member_profile_USER_101')))
        .onTap!();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('remove_group_member_button')),
      200,
      scrollable: find.byType(Scrollable).last,
    );

    await tester.tap(find.byKey(const Key('remove_group_member_button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('confirm_remove_group_member_button')),
    );
    await tester.pumpAndSettle();

    expect(controller.activeGroup!.memberIds, isNot(contains('USER_101')));
    expect(find.text('Farah Imani'), findsNothing);
  });

  testWidgets('choosing-next actions use concise navigation copy', (
    tester,
  ) async {
    await controller.openGroup('GROUP_001');
    await controller.confirmGroup();
    await controller.confirmSuggestion(
      controller.suggestions.firstWhere((item) => item.id == 'SUGGESTION_002'),
    );
    await controller.startItinerary();
    await controller.completeStop(controller.itinerary.first);
    await tester.pumpWidget(
      MaterialApp(home: GroupLobbyScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('start_next_lobby_leg')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Enjoy the current stop'), findsNothing);
    expect(find.text('Start Navigation'), findsOneWidget);
    expect(find.textContaining('Start next:'), findsNothing);

    await tester.tap(find.text('Itinerary').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('start_next_itinerary_leg')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Start Navigation'), findsOneWidget);
    expect(find.textContaining('Start navigation to'), findsNothing);
  });

  test(
    'zeroed itinerary legs are calculated when the workspace loads',
    () async {
      await controller.openGroup('GROUP_001');
      await controller.confirmSuggestion(
        controller.suggestions.firstWhere(
          (item) => item.id == 'SUGGESTION_002',
        ),
      );
      final repositoryStops = await repository.getItinerary('GROUP_001');
      repositoryStops[1]
        ..travelTimeFromPreviousMinutes = 0
        ..travelDistanceFromPreviousKm = 0;

      await controller.refreshWorkspace();

      expect(
        controller.itinerary[1].travelTimeFromPreviousMinutes,
        greaterThan(0),
      );
      expect(
        controller.itinerary[1].travelDistanceFromPreviousKm,
        greaterThan(0),
      );
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
  bool? lastAreasOnly;

  @override
  Future<List<TravelGroupPlace>> search(
    String query, {
    bool placesOnly = true,
    bool areasOnly = false,
  }) async {
    lastAreasOnly = areasOnly;
    if (query.toLowerCase().contains('zzzz')) return const [];
    if (areasOnly && query.toLowerCase().contains('shah')) {
      return const [
        TravelGroupPlace(
          id: 'areas/shah-alam',
          name: 'Shah Alam',
          address: 'Selangor, Malaysia',
          latitude: 3.0738,
          longitude: 101.5183,
        ),
      ];
    }
    return const [
      TravelGroupPlace(
        id: 'places/klcc',
        name: 'KLCC Park',
        address: 'Kuala Lumpur City Centre, Kuala Lumpur',
        latitude: 3.1532,
        longitude: 101.7149,
      ),
    ];
  }

  @override
  Future<TravelGroupPlace> loadDetails(TravelGroupPlace place) async => place;

  @override
  Future<String> areaForCoordinates({
    required double latitude,
    required double longitude,
  }) async => 'Setia Alam';

  @override
  void dispose() {}
}
