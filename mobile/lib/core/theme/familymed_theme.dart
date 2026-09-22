import 'package:flutter/material.dart';

abstract final class FamilyMedColors {
  static const appBackground = Color(0xFFFFF9F3);
  static const surface = Colors.white;
  static const primary = Color(0xFF176B63);
  static const primarySoft = Color(0xFFDDEFEA);
  static const textPrimary = Color(0xFF17302D);
  static const textSecondary = Color(0xFF667873);
  static const border = Color(0xFFE6DED5);
  static const success = Color(0xFF2E7D5B);
  static const successSoft = Color(0xFFE4F4EA);
  static const warning = Color(0xFFC7684E);
  static const warningSoft = Color(0xFFFCE9E2);
}

abstract final class FamilyMedTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: FamilyMedColors.appBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: FamilyMedColors.primary,
          brightness: Brightness.light,
          surface: FamilyMedColors.surface,
        ).copyWith(error: FamilyMedColors.warning),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: FamilyMedColors.textPrimary,
          ),
          headlineMedium: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: FamilyMedColors.textPrimary,
          ),
          titleMedium: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: FamilyMedColors.textPrimary,
          ),
          bodyMedium: TextStyle(
            fontSize: 15,
            height: 1.45,
            color: FamilyMedColors.textPrimary,
          ),
          labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );
}
