import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_app/app_shell/ohmy_app.dart';
import 'package:flutter_app/travel_group/features/travel_group/controllers/travel_group_controller.dart';
import 'package:flutter_app/travel_group/features/travel_group/models/travel_group_models.dart';
import 'package:flutter_app/travel_group/features/travel_group/repositories/mock_travel_group_repository.dart';
import 'package:flutter_app/travel_group/features/travel_group/screens/travel_group_discovery_screen.dart';
import 'package:flutter_app/travel_group/features/travel_group/screens/active_itinerary_map_screen.dart';
import 'package:flutter_app/travel_group/features/travel_group/screens/group_lobby_screen.dart';
import 'package:flutter_app/travel_group/features/travel_group/screens/group_details_screen.dart';
import 'package:flutter_app/travel_group/features/travel_group/screens/itinerary_board.dart';
import 'package:flutter_app/travel_group/features/travel_group/screens/suggestion_board.dart';
import 'package:flutter_app/travel_group/features/travel_group/services/live_trip_location_service.dart';
import 'package:flutter_app/travel_group/features/travel_group/services/travel_place_search_service.dart';
import 'package:flutter_app/travel_group/features/travel_group/travel_group_routes.dart';

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

  testWidgets('start trip hub offers a direct return to the active group', (
    tester,
  ) async {
    await controller.restoreOngoingCreatedGroup();
    await tester.pumpWidget(
      MaterialApp(home: StartTripHubPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('return_to_group_from_hub_button')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('return_to_group_from_hub_button')));
    await tester.pumpAndSettle();
    expect(find.byType(GroupLobbyScreen), findsOneWidget);
    expect(find.text(controller.activeGroup!.name), findsWidgets);
  });

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

  testWidgets('nearby lobbies back control has a full touch target', (
    tester,
  ) async {
    await controller.openGroup('GROUP_001');
    await tester.pumpWidget(
      MaterialApp(home: GroupLobbyScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    final size = tester.getSize(
      find.byKey(const Key('nearby_lobbies_back_button')),
    );
    expect(size.height, 48);
    expect(size.width, greaterThan(140));
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
  });

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
      await tester.binding.setSurfaceSize(const Size(375, 812));
      addTearDown(() => tester.binding.setSurfaceSize(null));
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
              builder: (_, _) => ItineraryBoard(
                controller: controller,
                placeSearchService: placeSearch,
              ),
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
      await gesture.moveBy(const Offset(0, 360));
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

  testWidgets('traveller exits to nearby lobbies when creator ends session', (
    tester,
  ) async {
    await controller.openGroup('GROUP_001');
    final creator = controller.activeGroup!.creatorName;
    controller.switchUser(
      PrototypeUser(id: 'USER_101', name: 'Traveller', isVerified: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open_lobby_before_creator_ends'),
                onPressed: () {
                  final navigator = Navigator.of(context);
                  navigator.push<void>(
                    MaterialPageRoute<void>(
                      settings: const RouteSettings(
                        name: travelGroupDiscoveryRouteName,
                      ),
                      builder: (_) => const Scaffold(
                        body: Center(child: Text('Nearby lobbies')),
                      ),
                    ),
                  );
                  navigator.push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => GroupLobbyScreen(controller: controller),
                    ),
                  );
                },
                child: const Text('Nearby lobbies'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_lobby_before_creator_ends')));
    await tester.pumpAndSettle();
    await repository.endTrip('GROUP_001');
    await controller.refreshWorkspace();
    await tester.pumpAndSettle();

    expect(find.byType(GroupLobbyScreen), findsNothing);
    expect(find.text('Nearby lobbies'), findsOneWidget);
    expect(
      find.textContaining('$creator ended the Group Trip'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('discovery is destination-led and uses a right-side create FAB', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Group Trips'), findsOneWidget);
    expect(find.text('Petaling Street'), findsOneWidget);
    expect(find.text('Petaling Street Food Hunt'), findsOneWidget);
    expect(find.textContaining('km away'), findsNothing);
    expect(find.textContaining('within 10 km'), findsOneWidget);
    expect(find.textContaining('Verified'), findsNothing);
    expect(find.byKey(const Key('create_group_fab')), findsOneWidget);
  });

  testWidgets('area control opens a location picker', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('area_dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('Setia City Mall'), findsOneWidget);
  });

  testWidgets('area search accepts any Google location', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('area_dropdown')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('area_search_field')), 'Shah');
    await tester.pumpAndSettle();

    expect(placeSearch.lastAreasOnly, isFalse);
    expect(placeSearch.lastPlacesOnly, isFalse);
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

    expect(find.text('No locations found'), findsOneWidget);
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
    expect(find.text('Create Group Trip'), findsNothing);
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
    expect(
      find.byKey(const Key('suggestion_photo_SUGGESTION_001')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('suggestion_photo_SUGGESTION_001')))
          .height,
      160,
    );
    expect(find.textContaining('min estimated'), findsWidgets);
  });

  testWidgets('itinerary uses route timeline controls and shows meetup owner', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await controller.openGroup('GROUP_001');
    await controller.confirmGroup();
    await controller.confirmSuggestion(
      controller.suggestions.firstWhere((item) => item.id == 'SUGGESTION_002'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItineraryBoard(
            controller: controller,
            placeSearchService: placeSearch,
            onChooseNext: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('itinerary_meetup_summary')), findsOneWidget);
    expect(find.text('Meetup point set by the group creator'), findsOneWidget);
    expect(find.byKey(const Key('itinerary_direction_arrow')), findsWidgets);
    expect(
      tester
          .getCenter(find.byKey(const Key('itinerary_direction_arrow')).first)
          .dx,
      closeTo(187.5, 2),
    );
    expect(
      tester.getSize(find.byKey(const Key('itinerary_photo_STOP_001'))).width,
      78,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('choose_next_itinerary_stop')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('choose_next_itinerary_stop')), findsOneWidget);
    expect(find.byKey(const Key('add_itinerary_stop_button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'traveller returns to the completed itinerary when the creator arrives',
    (tester) async {
      await controller.openGroup('GROUP_001');
      await controller.confirmGroup();
      await controller.startItinerary();
      await controller.completeStop(controller.itinerary.first);
      controller.switchUser(
        PrototypeUser(id: 'USER_101', name: 'Farah', isVerified: true),
      );

      await tester.pumpWidget(
        MaterialApp(
          initialRoute: '/travel-group/active-navigation',
          onGenerateRoute: (settings) {
            return PageRouteBuilder<void>(
              settings: settings,
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              pageBuilder: (_, _, _) =>
                  settings.name == '/travel-group/active-navigation'
                  ? ActiveItineraryMapScreen(controller: controller)
                  : const Scaffold(
                      body: Center(child: Text('Itinerary underneath')),
                    ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ActiveItineraryMapScreen), findsNothing);
      expect(find.text('Itinerary underneath'), findsOneWidget);
      expect(find.textContaining('The group is spending time'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(home: GroupLobbyScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<IndexedStack>(find.byKey(const Key('group_lobby_tabs')))
            .index,
        2,
      );
      expect(controller.itinerary.first.status, StopStatus.completed);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'nearby picker starts with recommendations and debounces custom search',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 812));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await controller.openGroup('GROUP_001');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SuggestionBoard(
              controller: controller,
              placeSearchService: placeSearch,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('suggest_place_search')));
      await tester.pumpAndSettle();
      expect(find.text('Nearby suggestions'), findsOneWidget);
      expect(find.text('Nearby Recommendation'), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const Key('nearby_place_thumbnail')).first)
            .height,
        220,
      );
      expect(
        tester
            .getSize(find.byKey(const Key('nearby_place_thumbnail')).first)
            .width,
        greaterThan(300),
      );
      expect(find.byIcon(Icons.tune_rounded), findsNothing);

      await tester.enterText(
        find.byKey(const Key('nearby_place_search_field')),
        'museum',
      );
      await tester.pump(const Duration(milliseconds: 299));
      expect(placeSearch.customSearchCalls, 0);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();

      expect(placeSearch.customSearchCalls, 1);
      expect(placeSearch.lastCustomQuery, 'museum');
      expect(find.text('Search results within 10 km'), findsOneWidget);
      expect(find.text('Custom Museum'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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

  testWidgets('traveller has a red leave action at the bottom of the lobby', (
    tester,
  ) async {
    controller.switchUser(
      PrototypeUser(id: 'USER_101', name: 'Farah', isVerified: true),
    );
    await controller.openGroup('GROUP_001');
    await tester.pumpWidget(
      MaterialApp(home: GroupLobbyScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('leave_travel_group_button')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('leave_travel_group_button')),
    );
    expect(button.style?.backgroundColor?.resolve({}), const Color(0xFFB3261E));
  });

  testWidgets('traveller leaving the lobby returns to the previous screen', (
    tester,
  ) async {
    controller.switchUser(
      PrototypeUser(id: 'USER_101', name: 'Farah', isVerified: true),
    );
    await controller.openGroup('GROUP_001');
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open_group_lobby_for_leave_test'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => GroupLobbyScreen(controller: controller),
                  ),
                ),
                child: const Text('Open current lobby'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_group_lobby_for_leave_test')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('leave_travel_group_button')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('leave_travel_group_button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('confirm_leave_travel_group_button')),
    );
    await tester.pumpAndSettle();

    expect(controller.activeGroup, isNull);
    expect(find.text('Open current lobby'), findsOneWidget);
    expect(find.byType(GroupLobbyScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing activity tags show an error inside the creation form', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create_group_fab')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('group_title')), 'No tags');
    await tester.enterText(find.byKey(const Key('destination_search')), 'KLCC');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('destination_result_0')));
    await tester.enterText(
      find.byKey(const Key('group_description')),
      'Testing visible validation.',
    );
    await tester.scrollUntilVisible(
      find.text('Create group'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Create group'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Select at least one activity preference for group recommendations.',
      ),
      findsOneWidget,
    );
    expect(find.text('Create group'), findsOneWidget);
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
  bool? lastPlacesOnly;
  int customSearchCalls = 0;
  String? lastCustomQuery;

  @override
  Future<List<TravelGroupPlace>> search(
    String query, {
    bool placesOnly = true,
    bool areasOnly = false,
  }) async {
    lastAreasOnly = areasOnly;
    lastPlacesOnly = placesOnly;
    if (query.toLowerCase().contains('zzzz')) return const [];
    if (query.toLowerCase().contains('shah')) {
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
  Future<List<NearbyPlace>> nearbySuggestions({
    required double latitude,
    required double longitude,
    String? destinationPlaceId,
    List<String> preferences = const [],
  }) async => const [
    NearbyPlace(
      name: 'Nearby Recommendation',
      source: 'Recommender',
      category: 'Heritage',
      distanceKm: 0.8,
      crowdLevel: 'Unknown',
      durationMinutes: 60,
      tags: ['Heritage'],
      placeId: 'places/nearby',
      latitude: 3.14,
      longitude: 101.69,
    ),
  ];

  @override
  Future<List<NearbyPlace>> searchNearbyByText({
    required String query,
    required double latitude,
    required double longitude,
    double radiusKm = 10,
  }) async {
    customSearchCalls++;
    lastCustomQuery = query;
    return const [
      NearbyPlace(
        name: 'Custom Museum',
        source: 'Google Places search',
        category: 'Museum',
        distanceKm: 1.2,
        crowdLevel: 'Unknown',
        durationMinutes: 60,
        tags: ['Museum'],
        placeId: 'places/custom-museum',
        latitude: 3.15,
        longitude: 101.7,
      ),
    ];
  }

  @override
  Future<String> areaForCoordinates({
    required double latitude,
    required double longitude,
  }) async => 'Setia Alam';

  @override
  void dispose() {}
}
