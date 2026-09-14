import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/user_management/widgets/auth_page_layout.dart';
import 'package:flutter_app/user_management/widgets/profile_tab_background.dart';

void main() {
  for (final title in ['Welcome back!', 'Create account']) {
    testWidgets('$title supports the profile backdrop', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AuthPageLayout(
          title: title,
          subtitle: 'Plan your journeys',
          useProfileBackdrop: true,
          child: const TextField(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileTabBackground), findsOneWidget);
      expect(find.text(title), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'traveller');
      expect(find.text('traveller'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
