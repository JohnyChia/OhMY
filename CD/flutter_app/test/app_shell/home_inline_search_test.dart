import 'package:community_discovery/community_discovery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/app_shell/personalized_home_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../community_discovery/test/support/fake_community_repository.dart';

void main() {
  testWidgets('Home search uses an inline dismissible result overlay', (
    tester,
  ) async {
    final communityController = CommunityController(FakeCommunityRepository());
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalizedHomePage(
          communityController: communityController,
          onOpenSoloMap: (_) {},
          onOpenCommunity: () {},
          onOpenPost: (_) {},
        ),
      ),
    );
    await tester.pump();

    final searchField = find.widgetWithText(
      TextField,
      'Search Attractions ...',
    );
    expect(searchField, findsOneWidget);

    await tester.enterText(searchField, 'Ampang');
    await tester.pump();
    expect(find.text('Searching...'), findsOneWidget);
    final dropdown = find.byKey(const ValueKey('home-search-dropdown'));
    expect(dropdown, findsOneWidget);
    final dropdownRect = tester.getRect(dropdown);
    expect(dropdownRect.right, lessThanOrEqualTo(800));
    expect(dropdownRect.height, lessThanOrEqualTo(274));
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(Dialog), findsNothing);

    await tester.tapAt(const Offset(8, 300));
    await tester.pump();
    expect(find.text('Searching...'), findsNothing);

    await tester.enterText(searchField, 'Selangor');
    await tester.pump();
    expect(find.text('Searching...'), findsOneWidget);
    await tester.enterText(searchField, '');
    await tester.pump();
    expect(find.text('Searching...'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    communityController.dispose();
  });
}
