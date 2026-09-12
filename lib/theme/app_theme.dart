import 'package:flutter/material.dart';

class AppTheme {
  static const Color bgDark = Color(0xFF090D16);
  static const Color surfaceDark = Color(0xFF131B2A);
  static const Color cardDark = Color(0xFF1A2336);
  static const Color cardBorder = Color(0xFF263552);

  // Accents
  static const Color cyanAccent = Color(0xFF00E5FF);
  static const Color amberAccent = Color(0xFFFFB300);
  static const Color greenAccent = Color(0xFF00E676);
  static const Color purpleAccent = Color(0xFF7C4DFF);
  static const Color redAccent = Color(0xFFFF5252);

  static const Color textPrimary = Color(0xFFF0F4FC);
  static const Color textSecondary = Color(0xFF8E9BB5);
  static const Color textMuted = Color(0xFF5A6987);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDark,
      primaryColor: cyanAccent,
      colorScheme: const ColorScheme.dark(
        primary: cyanAccent,
        secondary: amberAccent,
        surface: surfaceDark,
        error: redAccent,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: cardBorder, width: 1),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cardDark,
        disabledColor: surfaceDark,
        selectedColor: cyanAccent.withValues(alpha: 0.2),
        secondarySelectedColor: amberAccent.withValues(alpha: 0.2),
        labelStyle: const TextStyle(color: textPrimary, fontSize: 12),
        secondaryLabelStyle: const TextStyle(color: amberAccent, fontSize: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: cardBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardDark,
        hintStyle: const TextStyle(color: textMuted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: cyanAccent, width: 1.5),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceDark,
        selectedItemColor: cyanAccent,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 10,
        selectedLabelStyle:
            TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
        unselectedLabelStyle:
            TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
      ),
    );
  }
}
