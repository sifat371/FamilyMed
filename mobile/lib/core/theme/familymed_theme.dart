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
  static const _radius = 16.0;

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: FamilyMedColors.primary,
      brightness: Brightness.light,
      surface: FamilyMedColors.surface,
    ).copyWith(
      primary: FamilyMedColors.primary,
      onPrimary: Colors.white,
      secondary: FamilyMedColors.primary,
      surface: FamilyMedColors.surface,
      onSurface: FamilyMedColors.textPrimary,
      outline: FamilyMedColors.border,
      outlineVariant: FamilyMedColors.border,
      error: FamilyMedColors.warning,
      errorContainer: FamilyMedColors.warningSoft,
    );

    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: FamilyMedColors.appBackground,
      colorScheme: scheme,
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineLarge: const TextStyle(
          fontSize: 32,
          height: 1.1,
          fontWeight: FontWeight.w700,
          color: FamilyMedColors.textPrimary,
        ),
        headlineMedium: const TextStyle(
          fontSize: 26,
          height: 1.12,
          fontWeight: FontWeight.w700,
          color: FamilyMedColors.textPrimary,
        ),
        headlineSmall: const TextStyle(
          fontSize: 22,
          height: 1.15,
          fontWeight: FontWeight.w700,
          color: FamilyMedColors.textPrimary,
        ),
        titleLarge: const TextStyle(
          fontSize: 20,
          height: 1.2,
          fontWeight: FontWeight.w700,
          color: FamilyMedColors.textPrimary,
        ),
        titleMedium: const TextStyle(
          fontSize: 18,
          height: 1.25,
          fontWeight: FontWeight.w600,
          color: FamilyMedColors.textPrimary,
        ),
        bodyLarge: const TextStyle(
          fontSize: 16,
          height: 1.4,
          color: FamilyMedColors.textPrimary,
        ),
        bodyMedium: const TextStyle(
          fontSize: 15,
          height: 1.4,
          color: FamilyMedColors.textPrimary,
        ),
        bodySmall: const TextStyle(
          fontSize: 13,
          height: 1.35,
          color: FamilyMedColors.textSecondary,
        ),
        labelLarge: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        labelMedium: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: FamilyMedColors.textSecondary,
        ),
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: FamilyMedColors.appBackground,
        foregroundColor: FamilyMedColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 22,
          height: 1.15,
          fontWeight: FontWeight.w700,
          color: FamilyMedColors.textPrimary,
        ),
        iconTheme: IconThemeData(color: FamilyMedColors.primary),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: FamilyMedColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: FamilyMedColors.border),
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          backgroundColor: FamilyMedColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: FamilyMedColors.primarySoft,
          disabledForegroundColor: FamilyMedColors.textSecondary,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          foregroundColor: FamilyMedColors.primary,
          backgroundColor: FamilyMedColors.surface,
          side: const BorderSide(color: FamilyMedColors.border),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: FamilyMedColors.primary,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: FamilyMedColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 15,
        ),
        labelStyle: const TextStyle(
          color: FamilyMedColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: const TextStyle(color: FamilyMedColors.textSecondary),
        border: OutlineInputBorder(
          borderSide: const BorderSide(color: FamilyMedColors.border),
          borderRadius: BorderRadius.circular(_radius),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: FamilyMedColors.border),
          borderRadius: BorderRadius.circular(_radius),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(
            color: FamilyMedColors.primary,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(_radius),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: FamilyMedColors.warning),
          borderRadius: BorderRadius.circular(_radius),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: const BorderSide(
            color: FamilyMedColors.warning,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(_radius),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: FamilyMedColors.primarySoft,
        selectedColor: FamilyMedColors.primarySoft,
        side: BorderSide.none,
        labelStyle: const TextStyle(
          color: FamilyMedColors.primary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 74,
        elevation: 0,
        backgroundColor: FamilyMedColors.surface,
        indicatorColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected
                ? FamilyMedColors.primary
                : FamilyMedColors.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? FamilyMedColors.primary
                : FamilyMedColors.textSecondary,
          );
        }),
      ),
      dividerTheme: const DividerThemeData(
        color: FamilyMedColors.border,
        thickness: 1,
      ),
    );
  }
}
