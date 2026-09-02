import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/travel_group/controllers/travel_group_controller.dart';
import 'features/travel_group/screens/travel_group_discovery_screen.dart';

class TravelGroupApp extends StatelessWidget {
  const TravelGroupApp({super.key, required this.controller});

  final TravelGroupController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Travel Group Prototype',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: TravelGroupDiscoveryScreen(controller: controller),
    );
  }
}
