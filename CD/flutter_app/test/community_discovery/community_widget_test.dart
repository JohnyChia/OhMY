import 'package:flutter_app/community_discovery/community_app.dart';
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
}
