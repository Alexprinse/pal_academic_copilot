import 'package:flutter/material.dart';

class AppTheme {
  // Warm Paper & Scholarly Gold Palette
  static const Color canvasBg = Color(0xFFFBF9F4);
  static const Color cardSurface = Color(0xFFFFFFFF);
  static const Color cardBorder = Color(0xFFEAE6DC);

  static const Color textPrimary = Color(0xFF1E1D19);
  static const Color textSecondary = Color(0xFF706C62);
  static const Color textInactive = Color(0xFF9C9686);

  static const Color primaryAccent = Color(0xFFB88628);
  static const Color darkSurface = Color(0xFF1E1D19);

  // Semantic Pill Tokens
  static const Color trustPillFill = Color(0xFFEAF2EC);
  static const Color trustPillText = Color(0xFF2D6A4F);

  static const Color detectedPillFill = Color(0xFFFDF4E7);
  static const Color detectedPillText = Color(0xFF9C631A);

  static const Color overduePillFill = Color(0xFFFBEAE7);
  static const Color overduePillText = Color(0xFFC0392B);

  static const Color neutralPillFill = Color(0xFFF0EDE3);
  static const Color neutralPillText = Color(0xFF706C62);

  static const Color highlightBg = Color(0xFFFFF2D6);

  // Transitional compatibility aliases for remaining screens being upgraded
  static const Color bgDark = canvasBg;
  static const Color surfaceDark = cardSurface;
  static const Color cardDark = cardSurface;
  static const Color cardBorderDark = cardBorder;
  static const Color cyanAccent = primaryAccent;
  static const Color amberAccent = primaryAccent;
  static const Color purpleAccent = primaryAccent;
  static const Color greenAccent = trustPillText;
  static const Color redAccent = overduePillText;
  static const Color textMuted = textSecondary;

  static ThemeData get darkTheme => lightTheme;

  // Soft diffused elevation card shadow
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x0A1E1D19), // 4% rgba(30,29,25,0.04)
      blurRadius: 10,
      offset: Offset(0, 2),
    ),
    BoxShadow(
      color: Color(0x081E1D19), // 3% rgba(30,29,25,0.03)
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  static BoxDecoration get cardDecoration => BoxDecoration(
        color: cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder, width: 1),
        boxShadow: cardShadow,
      );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: canvasBg,
      primaryColor: primaryAccent,
      colorScheme: const ColorScheme.light(
        primary: primaryAccent,
        secondary: primaryAccent,
        surface: cardSurface,
        error: overduePillText,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: canvasBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: cardSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: cardBorder, width: 1),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: cardSurface,
        selectedItemColor: textPrimary,
        unselectedItemColor: textInactive,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: textPrimary,
        ),
        unselectedLabelStyle: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 12,
          color: textInactive,
        ),
      ),
    );
  }
}
