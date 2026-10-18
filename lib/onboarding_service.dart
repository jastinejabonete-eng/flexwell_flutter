import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  static const _completedKey = 'onboarding_tour_completed_v1';

  static Future<bool> hasCompletedTour() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getBool(_completedKey) ?? false;
    } catch (error) {
      debugPrint('Reading onboarding completion failed: $error');
      return false;
    }
  }

  static Future<void> markTourCompleted() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = await preferences.setBool(_completedKey, true);
      if (!saved) {
        debugPrint('Saving onboarding completion failed.');
      }
    } catch (error) {
      debugPrint('Saving onboarding completion failed: $error');
    }
  }
}
