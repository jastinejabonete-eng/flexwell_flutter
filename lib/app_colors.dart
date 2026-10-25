import 'package:flutter/material.dart';

class AppColors {
  // Brand palette
  static const brandBlue = Color(0xFF086288);
  static const brandMidBlue = Color(0xFF4D8DBA);
  static const brandSkyBlue = Color(0xFF97D7FF);
  static const warmHighlight = Color(0xFFFFEFC4);

  // Status & Feedback Colors
  static const correct = Color(0xFF2ECC71); // High-Vis Form Correct
  static const incorrect = Color(0xFFE53935); // Warning Form Red

  // Dark theme surfaces and text
  static const darkBackground = Color(0xFF081A23);
  static const darkSurface = Color(0xFF0C2532);
  static const darkCard = Color(0xFF153645);
  static const darkBorder = Color(0xFF234856);
  static const darkCardFilled = Color(0xFF102D3A);
  static const darkText = Color(0xFFE3EDF4);
  static const darkTextSecondary = Color(0xFFACBDC9);

  // Light theme surfaces and text. The cool canvas separates white cards,
  // while the cream remains a distinct workout-completion highlight.
  static const lightBackground = Color(0xFFF0F8FE);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightRaised = Color(0xFFE6F0F7);
  static const lightAccentSubtle = Color(0xFFE7F4FD);
  static const lightBorder = Color(0xFFC5D3DD);
  static const lightStrongBorder = brandMidBlue;
  static const lightText = Color(0xFF232D33);
  static const lightTextSecondary = Color(0xFF4B575F);

  static const navBarBackground = darkSurface;
  static const navBarActivePill = darkCardFilled;
  static const navBarInactive = Color(0xFF99BAC8);

  static Color accentFor(bool isDark) => isDark ? brandSkyBlue : brandBlue;

  static Color onAccentFor(bool isDark) =>
      isDark ? darkBackground : Colors.white;

  static Color accentSubtleFor(bool isDark) =>
      isDark ? darkCard : lightAccentSubtle;

  static Color accentBorderFor(bool isDark) =>
      isDark ? brandSkyBlue : lightStrongBorder;

  static Color textFor(bool isDark) => isDark ? darkText : lightText;

  static Color secondaryTextFor(bool isDark) =>
      isDark ? darkTextSecondary : lightTextSecondary;

  // Achievement gold (unlocked badges / trophy accents).
  static const gold = Color(0xFFFFD700);
  // Locked/undone badge outline (achievements screen shields).
  static const badgeLocked = Color(0xFF94A3B8);
}
