import 'package:flutter/material.dart';

import 'screens/auth/auth_gate.dart';

class OhMyApp extends StatelessWidget {
  const OhMyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E60C4),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'ohMY Travel',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
        fontFamily: 'Roboto',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAFF),
          labelStyle: const TextStyle(color: Color(0xFF63718B), fontSize: 10),
          floatingLabelStyle: const TextStyle(
            color: Color(0xFF63718B),
            fontSize: 10,
          ),
          hintStyle: const TextStyle(color: Color(0xFF7B879B), fontSize: 14),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFC4D5F8)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFC4D5F8)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF2E60C4), width: 2),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2E60C4),
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xFF9BB3E4),
            elevation: 5,
            shadowColor: const Color(0x38143373),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(fontSize: 15),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}
