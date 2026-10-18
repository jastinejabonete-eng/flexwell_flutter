import 'dart:async';

import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'firebase_status.dart';
import 'main_navigation_screen.dart';
import 'theme_preference.dart';
import 'terms_screen.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

ThemeData _buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final foreground = isDark ? Colors.white : AppColors.lightText;
  final secondary = isDark ? AppColors.primaryLight : AppColors.accentText;
  final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
  final outline = isDark ? AppColors.darkBorder : AppColors.lightBorder;
  final scheme = ColorScheme.fromSeed(
    seedColor: isDark ? AppColors.accent : AppColors.primary,
    brightness: brightness,
    primary: isDark ? AppColors.accent : AppColors.primary,
    onPrimary: isDark ? Colors.black : Colors.white,
    secondary: secondary,
    onSecondary: Colors.white,
    surface: surface,
    onSurface: foreground,
    error: AppColors.incorrect,
  ).copyWith(outline: outline);

  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  );
  final buttonStyle = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    ),
    shape: WidgetStatePropertyAll(shape),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark
        ? AppColors.darkBackground
        : AppColors.lightBackground,
    cardColor: isDark ? AppColors.darkCardFilled : AppColors.lightCard,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: foreground,
      titleTextStyle: TextStyle(
        color: foreground,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: outline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? AppColors.darkCardFilled : AppColors.lightSurface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: buttonStyle.copyWith(
        backgroundColor: WidgetStatePropertyAll(AppColors.accent),
        foregroundColor: const WidgetStatePropertyAll(Colors.black),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: buttonStyle.copyWith(
        backgroundColor: WidgetStatePropertyAll(AppColors.accent),
        foregroundColor: const WidgetStatePropertyAll(Colors.black),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: buttonStyle.copyWith(
        side: WidgetStatePropertyAll(BorderSide(color: outline)),
        foregroundColor: WidgetStatePropertyAll(foreground),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: buttonStyle.copyWith(
        foregroundColor: WidgetStatePropertyAll(scheme.primary),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size.square(48),
        foregroundColor: foreground,
      ),
    ),
    listTileTheme: const ListTileThemeData(
      minVerticalPadding: 10,
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: outline),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? AppColors.darkCard : const Color(0xFF263238),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: isDark
          ? Colors.white.withValues(alpha: 0.12)
          : AppColors.lightBorder,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.18 : 0.12),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        );
      }),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: surface,
      indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.18 : 0.12),
      selectedIconTheme: IconThemeData(color: scheme.primary),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseStatus.initialize();
  themeNotifier.value = await ThemePreference.load();
  final termsAccepted = await TermsService.hasAccepted();
  runApp(FlexWellApp(termsAccepted: termsAccepted));
  if (FirebaseStatus.isInitialized) {
    unawaited(FirebaseStatus.ensureSignedIn());
  }
}

class FlexWellApp extends StatelessWidget {
  /// False on first launch (or after the terms version is bumped).
  final bool termsAccepted;

  const FlexWellApp({super.key, required this.termsAccepted});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentTheme, child) {
        return MaterialApp(
          title: 'FlexWell',
          debugShowCheckedModeBanner: false,
          themeMode: currentTheme,
          // Defaults to Duration.zero, which is why the light/dark toggle
          // snapped instantly and janked (all the heavy dark-mode box-shadows
          // rebuild in a single frame). A short duration cross-fades the whole
          // theme, spreading that rebuild across the animation.
          themeAnimationDuration: const Duration(milliseconds: 200),
          themeAnimationCurve: Curves.easeInOut,

          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          home: termsAccepted
              ? const MainNavigationScreen()
              : const TermsScreen(requireAcceptance: true),
        );
      },
    );
  }
}
