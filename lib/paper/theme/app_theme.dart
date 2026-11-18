import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryGreen = Color(0xFF20B77A);
  static const Color accentGreenLight = Color(0xFF34D399);
  static const Color candleYellow = Color(0xFFF2C94C);
  static const Color candleRed = Color(0xFFE65A52);
  static const Color infoBlue = Color(0xFF3B82F6);
  static const Color purpleAccent = Color(0xFFA855F7);

  // Dark Theme Palette (OLED friendly)
  static const Color darkBackground = Color(0xFF101411);
  static const Color darkSurface = Color(0xFF18201B);
  static const Color darkCard = Color(0xFF1E2822);
  static const Color darkBorder = Color(0xFF2B3A31);
  static const Color darkTextPrimary = Color(0xFFF0FDF4);
  static const Color darkTextSecondary = Color(0xFF9EABA2);

  // Light Theme Palette
  static const Color lightBackground = Color(0xFFF7FAF8);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE1E8E3);
  static const Color lightTextPrimary = Color(0xFF131B15);
  static const Color lightTextSecondary = Color(0xFF5F6E64);

  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: primaryGreen,
        secondary: accentGreenLight,
        surface: darkSurface,
        onSurface: darkTextPrimary,
        error: candleRed,
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: darkTextPrimary),
        titleTextStyle: TextStyle(
          color: darkTextPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.3,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: darkBorder,
        thickness: 1,
        space: 24,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: darkTextPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          height: 1.3,
        ),
        titleLarge: TextStyle(
          color: darkTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          height: 1.35,
        ),
        titleMedium: TextStyle(
          color: primaryGreen,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        bodyLarge: TextStyle(
          color: darkTextPrimary,
          fontSize: 15,
          height: 1.6,
          letterSpacing: 0.1,
        ),
        bodyMedium: TextStyle(
          color: darkTextSecondary,
          fontSize: 13.5,
          height: 1.5,
        ),
        labelSmall: TextStyle(
          color: darkTextSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  static ThemeData light() {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBackground,
      colorScheme: const ColorScheme.light(
        primary: primaryGreen,
        secondary: primaryGreen,
        surface: lightSurface,
        onSurface: lightTextPrimary,
        error: candleRed,
      ),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: lightBorder, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: lightBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: lightTextPrimary),
        titleTextStyle: TextStyle(
          color: lightTextPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.3,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: lightBorder,
        thickness: 1,
        space: 24,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: lightTextPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          height: 1.3,
        ),
        titleLarge: TextStyle(
          color: lightTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          height: 1.35,
        ),
        titleMedium: TextStyle(
          color: primaryGreen,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        bodyLarge: TextStyle(
          color: lightTextPrimary,
          fontSize: 15,
          height: 1.6,
          letterSpacing: 0.1,
        ),
        bodyMedium: TextStyle(
          color: lightTextSecondary,
          fontSize: 13.5,
          height: 1.5,
        ),
        labelSmall: TextStyle(
          color: lightTextSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
