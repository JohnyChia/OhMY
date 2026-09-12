import 'package:flutter/material.dart';

import 'data/community_repository.dart';
import 'state/community_controller.dart';
import 'theme/community_theme.dart';
import 'ui/community_feed_screen.dart';

class CommunityApp extends StatefulWidget {
  const CommunityApp({super.key, required this.repository});

  final CommunityRepository repository;

  @override
  State<CommunityApp> createState() => _CommunityAppState();
}

class _CommunityAppState extends State<CommunityApp> {
  late final CommunityController controller;

  @override
  void initState() {
    super.initState();
    controller = CommunityController(widget.repository);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Community Discovery',
    debugShowCheckedModeBanner: false,
    theme: buildCommunityTheme(),
    home: CommunityFeedScreen(controller: controller),
  );
}
