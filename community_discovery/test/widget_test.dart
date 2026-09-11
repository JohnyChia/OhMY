import 'package:community_discovery/src/community_app.dart';
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
    expect(find.text('Morning light at Kwai Chai Hong'), findsOneWidget);
    expect(find.text('Open sample Trip History'), findsNothing);
    expect(find.text('Sign in'), findsNothing);

    await tester.tap(find.byTooltip('All tags'));
    await tester.pumpAndSettle();
    expect(find.text('0 selected'), findsOneWidget);
    expect(find.text('Heritage'), findsWidgets);
    expect(find.text('Show all posts'), findsOneWidget);
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
}
