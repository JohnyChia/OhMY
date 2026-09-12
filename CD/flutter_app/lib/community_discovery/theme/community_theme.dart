import 'package:flutter/material.dart';

abstract final class CommunityColors {
  static const primary = Color(0xFF3667CF);
  static const headerStart = Color(0xFFE8E4FF);
  static const headerEnd = Color(0xFF8FB5FF);
  static const surface = Color(0xFFF6F8FC);
  static const ink = Color(0xFF172641);
}

ThemeData buildCommunityTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: CommunityColors.primary,
    brightness: Brightness.light,
    surface: CommunityColors.surface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: CommunityColors.surface,
    fontFamily: 'sans-serif',
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: CommunityColors.ink,
      elevation: 0,
      centerTitle: true,
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        side: BorderSide(color: Color(0xFFD8E2F2)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
