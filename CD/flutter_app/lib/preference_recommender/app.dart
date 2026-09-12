import 'package:flutter/material.dart';

import 'pages/place_map_page.dart';

/// Standalone application shell for the Preference Recommender module.
class PreferenceRecommenderApp extends StatelessWidget {
  const PreferenceRecommenderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ohMY',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff3266cc)),
        scaffoldBackgroundColor: const Color(0xfff8fbff),
      ),
      home: const PlaceMapPage(),
    );
  }
}
