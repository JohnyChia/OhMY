import 'package:flutter/material.dart';
import 'package:flutter_app/user_management/screens/travel_preferences_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('all preferences and Continue fit on a short phone screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: TravelPreferencesScreen(onSaved: (_) {}),
      ),
    );

    final continueButton = find.widgetWithText(FilledButton, 'Continue');
    expect(find.byTooltip('Back'), findsNothing);
    expect(find.byType(Scrollable), findsNothing);
    expect(find.text('Traditional Craft').hitTestable(), findsOneWidget);
    expect(continueButton.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing returns draft selections through Back without saving', (
    tester,
  ) async {
    List<String>? draft;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => TravelPreferencesScreen(
                    isEditing: true,
                    initialSelections: const [
                      'Heritage', 'Local Cuisine', 'Historical Landmark',
                    ],
                    onSaved: (value) => draft = value,
                  ),
                ),
              ),
              child: const Text('Edit interests'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit interests'));
    await tester.pumpAndSettle();
    expect(find.text('Save preferences'), findsNothing);
    expect(find.text('Continue'), findsNothing);
    await tester.ensureVisible(find.text('Cultural Experience'));
    await tester.tap(find.text('Cultural Experience'));
    await tester.pump();
    expect(draft, isNull);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(draft, contains('Cultural Experience'));
    expect(draft, hasLength(4));
  });
}
