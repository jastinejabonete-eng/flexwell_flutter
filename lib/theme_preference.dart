import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemePreference {
  ThemePreference._();

  static const _key = 'theme_mode';

  static Future<ThemeMode> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getBool(_key) ?? true
          ? ThemeMode.dark
          : ThemeMode.light;
    } catch (error) {
      debugPrint('Loading theme preference failed: $error');
      return ThemeMode.dark;
    }
  }

  static Future<void> save(ThemeMode mode) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = await preferences.setBool(_key, mode == ThemeMode.dark);
      if (!saved) debugPrint('Saving theme preference failed.');
    } catch (error) {
      debugPrint('Saving theme preference failed: $error');
    }
  }
}
