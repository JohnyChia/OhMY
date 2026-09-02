import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xFF3266CC);
  static const primaryDark = Color(0xFF214A9A);
  static const ink = Color(0xFF17243D);
  static const secondaryText = Color(0xFF62708A);
  static const border = Color(0xFFB8D1FA);
  static const surfaceBlue = Color(0xFFE8F2FF);
  static const paleBlue = Color(0xFFF0F6FF);
  static const surfaceLavender = Color(0xFFF7F2FF);
  static const surfaceWarm = Color(0xFFFFF6E8);
  static const success = Color(0xFF1F8F57);
  static const successSurface = Color(0xFFE8F7ED);
  static const warning = Color(0xFFF59E24);
  static const page = Color(0xFFFFFFFF);
}

abstract final class AppTheme {
  static ThemeData get light {
    const scheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: AppColors.ink,
      outline: AppColors.border,
      error: Color(0xFFBF2424),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.page,
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineMedium:
            TextStyle(fontSize: 25, height: 1.15, color: AppColors.ink),
        titleLarge: TextStyle(fontSize: 21, height: 1.2, color: AppColors.ink),
        titleMedium: TextStyle(fontSize: 16, height: 1.2, color: AppColors.ink),
        bodyMedium: TextStyle(fontSize: 13, height: 1.35, color: AppColors.ink),
        bodySmall: TextStyle(
            fontSize: 11, height: 1.35, color: AppColors.secondaryText),
        labelSmall: TextStyle(
            fontSize: 10, height: 1.2, color: AppColors.secondaryText),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 44),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.border),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 11),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8F7FB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}
