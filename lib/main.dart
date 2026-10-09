import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'app_colors.dart';
import 'main_navigation_screen.dart';
import 'terms_screen.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
      debugPrint('Anonymous user authenticated: ${FirebaseAuth.instance.currentUser?.uid}');
    }
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }
  final termsAccepted = await TermsService.hasAccepted();
  runApp(FlexWellApp(termsAccepted: termsAccepted));
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
          
          // Light Mode Theme
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: AppColors.lightBackground,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.primary,
              brightness: Brightness.light,
              primary: AppColors.primary,
              secondary: AppColors.accent,
              surface: AppColors.lightSurface,
              error: AppColors.incorrect,
            ),
            cardColor: AppColors.lightCard,
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: false,
              titleTextStyle: TextStyle(
                color: Colors.black87,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: AppColors.lightSurface,
              selectedItemColor: AppColors.primary,
              unselectedItemColor: AppColors.neutral,
              elevation: 8,
            ),
          ),

          // Dark Mode Theme (Default Gym Vibe)
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: AppColors.darkBackground,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.primary,
              brightness: Brightness.dark,
              primary: AppColors.primary,
              secondary: AppColors.accent,
              surface: AppColors.darkSurface,
              error: AppColors.incorrect,
            ),
            cardColor: AppColors.darkCard,
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: false,
              titleTextStyle: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: AppColors.darkSurface,
              selectedItemColor: AppColors.accent,
              unselectedItemColor: AppColors.neutral,
              elevation: 8,
            ),
          ),
          home: termsAccepted
              ? const MainNavigationScreen()
              : const TermsScreen(requireAcceptance: true),
        );
      },
    );
  }
}