import 'package:community_discovery/src/community_app.dart';
import 'package:community_discovery/src/integration/community_integration_callbacks.dart';
import 'package:community_discovery/src/state/community_controller.dart';
import 'package:community_discovery/src/ui/community_feed_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_community_repository.dart';

void main() {
  testWidgets('shows the integration-ready Community feed', (tester) async {
    await tester.pumpWidget(
      CommunityApp(repository: FakeCommunityRepository()),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Community finds'), findsOneWidget);
    expect(find.text('Posts from completed trips'), findsNothing);
    expect(find.text('Morning light at Kwai Chai Hong'), findsOneWidget);
    expect(find.text('Open sample Trip History'), findsNothing);
    expect(find.text('Sign in'), findsNothing);

    await tester.tap(find.byTooltip('Sort and filter'));
    await tester.pumpAndSettle();
    expect(find.text('0 selected'), findsOneWidget);
    expect(find.text('Heritage'), findsWidgets);
    expect(find.text('Apply and show all'), findsOneWidget);
  });

  testWidgets('host app can hide standalone Community navigation', (
    tester,
  ) async {
    final controller = CommunityController(FakeCommunityRepository());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: CommunityFeedScreen(
          controller: controller,
          showBottomNavigation: false,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Community finds'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('community header offers latest and most liked sorting', (
    tester,
  ) async {
    final controller = CommunityController(FakeCommunityRepository());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: CommunityFeedScreen(controller: controller)),
    );
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byTooltip('Sort and filter'));
    await tester.pumpAndSettle();
    expect(find.text('Latest'), findsOneWidget);
    await tester.tap(find.text('Most liked'));
    await tester.pumpAndSettle();
    final sortControl = tester.widget(
      find.byWidgetPredicate((widget) => widget is SegmentedButton),
    );
    expect(
      (sortControl as dynamic).selected.single.toString(),
      contains('mostLiked'),
    );
  });

  testWidgets('only matching preference tags appear below the heading', (
    tester,
  ) async {
    final controller = CommunityController(FakeCommunityRepository());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: CommunityFeedScreen(
          controller: controller,
          preferredTagNames: const ['Local Cuisine'],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Heritage'), findsNothing);
    expect(
      find.text('No saved preference tags are available.'),
      findsOneWidget,
    );
  });

  testWidgets('an author sees delete controls but cannot bookmark own post', (
    tester,
  ) async {
    final controller = CommunityController(
      FakeCommunityRepository(isOwner: true),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: CommunityFeedScreen(controller: controller)),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byTooltip('Bookmark'), findsNothing);
    await tester.tap(find.text('Morning light at Kwai Chai Hong'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Edit post'), findsOneWidget);
    expect(find.byTooltip('Delete post'), findsOneWidget);
    expect(find.text('Bookmark'), findsNothing);

    await tester.tap(find.byTooltip('Edit post'));
    await tester.pumpAndSettle();
    expect(find.text('Edit post'), findsOneWidget);
    expect(find.byTooltip('Delete post'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete post'));
    await tester.pumpAndSettle();
    expect(find.text('Delete permanently?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete post'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Community finds'), findsOneWidget);
    expect(find.text('Morning light at Kwai Chai Hong'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('submitting a comment refreshes without a setState error', (
    tester,
  ) async {
    final controller = CommunityController(FakeCommunityRepository());
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: CommunityFeedScreen(controller: controller)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Morning light at Kwai Chai Hong'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Send comment'));
    await tester.pump();
    expect(find.text('Comments must be 1–500 characters.'), findsOneWidget);
    final commentField = tester.widget<TextField>(find.byType(TextField));
    expect(
      commentField.decoration?.errorText,
      'Comments must be 1–500 characters.',
    );

    await tester.enterText(find.byType(TextField), 'Useful travel tip');
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration?.errorText,
      isNull,
    );
    await tester.ensureVisible(find.byTooltip('Send comment'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Send comment'));
    await tester.pumpAndSettle();

    expect(find.text('Useful travel tip'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the post location invokes the Start Trip callback', (
    tester,
  ) async {
    final controller = CommunityController(FakeCommunityRepository());
    addTearDown(controller.dispose);
    StartJourneyRequest? request;

    await tester.pumpWidget(
      MaterialApp(
        home: CommunityFeedScreen(
          controller: controller,
          integrationCallbacks: CommunityIntegrationCallbacks(
            onStartJourney: (value) => request = value,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Morning light at Kwai Chai Hong'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.directions_outlined));
    await tester.pump();

    expect(request?.attractionName, 'Kwai Chai Hong');
    expect(request?.destinationName, 'Kuala Lumpur');
  });
}
