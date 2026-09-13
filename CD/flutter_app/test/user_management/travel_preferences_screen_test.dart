import 'package:flutter/material.dart';
import 'package:flutter_app/user_management/screens/travel_preferences_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('continue button can be reached on a short phone screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: TravelPreferencesScreen(onSaved: (_) {})),
    );

    final continueButton = find.widgetWithText(FilledButton, 'Continue');
    expect(continueButton, findsOneWidget);
    expect(continueButton.hitTestable(), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(continueButton.hitTestable(), findsOneWidget);
  });
}
