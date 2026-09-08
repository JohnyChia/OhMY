import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/travel_group/app.dart';
import 'package:flutter_app/travel_group/features/travel_group/controllers/travel_group_controller.dart';
import 'package:flutter_app/travel_group/features/travel_group/repositories/mock_travel_group_repository.dart';

void main() {
  testWidgets('TravelGroupApp smoke test', (WidgetTester tester) async {
    final repository = MockTravelGroupRepository.seeded();
    final controller = TravelGroupController(repository: repository);

    await tester.pumpWidget(TravelGroupApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Nearby lobbies'), findsOneWidget);
  });
}
