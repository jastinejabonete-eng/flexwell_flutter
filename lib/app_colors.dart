import 'package:flutter/material.dart';

class AppColors {
  // Gym Theme Brand Colors
  static const primary = Color(0xFF0D47A1); // Athletic Deep Navy/Blue
  static const primaryLight = Color(0xFF1976D2);
  static const accent = Color(0xFFCCFF00); // Electric Gym Volt / Neon Yellow-Green
  static const accentDark = Color(0xFF99CC00);

  // Status & Feedback Colors
  static const correct = Color(0xFF2ECC71); // High-Vis Form Correct
  static const incorrect = Color(0xFFE53935); // Warning Form Red
  static const neutral = Color(0xFF757575);

  // Dark Theme Palette (Gym Aesthetics)
  static const darkBackground = Color(0xFF121418);
  static const darkSurface = Color(0xFF1A1F26);
  static const darkCard = Color(0xFF222831);
  static const darkBorder = Color(0xFF2C3440);
  // The raised card fill actually used across screens (kept distinct from
  // darkCard so both stay available; migrate call sites onto these).
  static const darkCardFilled = Color(0xFF1E232A);

  // Light Theme Palette
  // Cool grey-blue page background so white cards stand out from it.
  static const lightBackground = Color(0xFFEEF2F7);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightBorder = Color(0xFFD5DDE8);
  // Slate text: softer than pure black, still >= 7:1 on white.
  static const lightText = Color(0xFF0F172A);
  static const lightTextSecondary = Color(0xFF475569);
  // Deep lime-green for TEXT / ICONS / BORDERS on light surfaces. The neon
  // volt (#CCFF00) is almost invisible on white; use it only as a fill.
  static const accentText = Color(0xFF3F6212);

  // Bottom navigation bar (the floating pill in main_navigation_screen).
  static const navBarBackground = Color(0xFF0F172A);
  static const navBarActivePill = Color(0xFF1E293B);
  static const navBarInactive = Color(0xFF64748B);

  // Achievement gold (unlocked badges / trophy accents).
  static const gold = Color(0xFFFFD700);
  // Locked/undone badge outline (achievements screen shields).
  static const badgeLocked = Color(0xFF94A3B8);

  /// Volt in dark mode, readable deep green in light mode.
  static Color voltFor(bool isDark) => isDark ? accent : accentText;
}