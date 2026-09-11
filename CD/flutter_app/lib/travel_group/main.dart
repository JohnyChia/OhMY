import 'package:flutter/material.dart';

import 'app.dart';
import 'features/travel_group/controllers/travel_group_controller.dart';
import 'features/travel_group/repositories/mock_travel_group_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = MockTravelGroupRepository.seeded();
  final controller = TravelGroupController(repository: repository);
  runApp(TravelGroupApp(controller: controller));
}
