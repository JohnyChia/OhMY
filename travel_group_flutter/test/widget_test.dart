import 'package:flutter_test/flutter_test.dart';
import 'package:travel_group_prototype/app.dart';
import 'package:travel_group_prototype/features/travel_group/controllers/travel_group_controller.dart';
import 'package:travel_group_prototype/features/travel_group/repositories/mock_travel_group_repository.dart';

void main() {
  testWidgets('TravelGroupApp smoke test', (WidgetTester tester) async {
    final repository = MockTravelGroupRepository.seeded();
    final controller = TravelGroupController(repository: repository);

    await tester.pumpWidget(TravelGroupApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Nearby lobbies'), findsOneWidget);
  });
}
