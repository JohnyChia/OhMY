import 'package:flutter/material.dart';
import 'package:flutter_app/preference_recommender/features/routes/route_feature.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('start and destination share recommended and saved filters', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DirectionsSetupPage(
          backend: 'http://127.0.0.1:1',
          destination: RouteLocation(
            id: 'destination-id',
            name: 'Batu Caves',
            address: 'Gombak, Selangor',
            latitude: 3.2379,
            longitude: 101.6840,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Recent'), findsNothing);
    expect(find.text('Suggested'), findsNothing);
    expect(find.text('Recommended'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Your Location'), findsOneWidget);

    await tester.tap(find.byType(TextField).at(1));
    await tester.pump();

    expect(find.text('Recommended'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Your Location'), findsNothing);
  });

  testWidgets('clear resets the destination query and preserves focus', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DirectionsSetupPage(
          backend: 'http://127.0.0.1:1',
          destination: RouteLocation(
            id: 'destination-id',
            name: 'Batu Caves',
            address: 'Gombak, Selangor',
            latitude: 3.2379,
            longitude: 101.6840,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('clear-route-location-1')));
    await tester.pump();

    final destinationField = tester.widget<TextField>(
      find.byType(TextField).at(1),
    );
    expect(destinationField.controller?.text, isEmpty);
    expect(destinationField.focusNode?.hasFocus, isTrue);
    expect(find.text('Recommended'), findsOneWidget);
  });
}
