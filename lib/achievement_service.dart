import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AchievementService {
  /// Sessions with fewer reliable frames than this (~3 s at 10 fps) are
  /// ignored, so tapping Stop immediately doesn't award anything.
  static const int minReliableFrames = 30;

  /// Minimum completed reps required before a "flawless session" can be
  /// awarded, so a single lucky rep doesn't trivially qualify.
  static const int minRepsForFlawlessAchievement = 5;

  /// Upper bound for any Firestore read, so the UI never waits forever
  /// while offline.
  static const Duration _readTimeout = Duration(seconds: 5);
  static const Duration _signInTimeout = Duration(seconds: 8);

  /// Returns the signed-in user, retrying anonymous sign-in if it failed at
  /// startup (e.g. first launch while offline). Retries a few times with a
  /// short backoff because the initial sign-in can lose a race with Firebase
  /// init. Never throws.
  static Future<User?> _ensureUser() async {
    final existing = FirebaseAuth.instance.currentUser;
    if (existing != null) return existing;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final cred = await FirebaseAuth.instance
            .signInAnonymously()
            .timeout(_signInTimeout);
        debugPrint('FlexWell: anonymous sign-in OK (uid=${cred.user?.uid})');
        return cred.user;
      } catch (e) {
        debugPrint('FlexWell: anonymous sign-in attempt '
            '${attempt + 1} failed: $e');
        await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    debugPrint('FlexWell: anonymous sign-in FAILED after retries -- '
        'sessions/achievements will NOT be saved.');
    return null;
  }

  static Future<CollectionReference<Map<String, dynamic>>?> _userCollection(
      String name) async {
    final user = await _ensureUser();
    if (user == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection(name);
  }

  /// Unlocks an achievement. Returns true only if it was newly unlocked.
  /// Never throws.
  static Future<bool> unlockAchievement(String achievementId) async {
    try {
      final col = await _userCollection('unlocked_achievements');
      if (col == null) return false;

      final docRef = col.doc(achievementId);
      final snapshot = await docRef.get().timeout(_readTimeout);
      if (snapshot.exists && (snapshot.data()?['unlocked'] ?? false) == true) {
        return false;
      }

      // Not awaited: Firestore only completes writes once the server
      // acknowledges them, which would stall while offline. The SDK queues
      // the write locally and sends it when the connection returns.
      unawaited(docRef.set({
        'unlocked': true,
        'unlockedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).then((_) {},
          onError: (Object e) =>
              debugPrint('Saving achievement $achievementId failed: $e')));

      debugPrint('Achievement $achievementId unlocked!');
      return true;
    } catch (e) {
      debugPrint('unlockAchievement($achievementId) failed: $e');
      return false;
    }
  }

  /// Unlocks the 'share' achievement, but ONLY if the user has already earned
  /// at least one WORKOUT badge. This stops Share from being a freebie that
  /// can be unlocked on first launch by tapping the share icon, before the
  /// user has done anything.
  ///
  /// Returns true ONLY when this call newly unlocked it (so the UI can show a
  /// one-time celebration popup). Returns false when the prerequisite isn't
  /// met, the badge was already unlocked, or the write couldn't be attempted.
  static Future<bool> unlockShareAchievement() async {
    try {
      final col = await _userCollection('unlocked_achievements');
      if (col == null) return false;
      final snap = await col.get().timeout(_readTimeout);
      final hasWorkoutBadge = snap.docs.any(
        (d) => d.id != 'share_achievement' &&
            d.id != 'share' &&
            (d.data()['unlocked'] == true),
      );
      if (!hasWorkoutBadge) return false;
      // Must match the catalog doc id ('share_achievement') so the unlocked
      // doc lines up with the catalog entry on the Achievements screen.
      // unlockAchievement returns true only when it was newly written.
      return await unlockAchievement('share_achievement');
    } catch (e) {
      debugPrint('unlockShareAchievement failed: $e');
      return false;
    }
  }

  /// Saves a finished session and evaluates every achievement.
  /// Returns the ids that were newly unlocked. Never throws.
  static Future<List<String>> recordSession({
    required String exercise,
    required int accuracy,
    required int reps,
    required int longestHold,
    required int reliableFrames,
    // How many of `reps` had zero incorrect-form frames during their
    // lifecycle (see CameraScreen's quality-tracked reps). Defaults to 0
    // for hold-based exercises and older call sites, where the concept
    // either doesn't apply or hasn't been wired up yet.
    int perfectReps = 0,
  }) async {
    final newlyUnlocked = <String>[];
    try {
      if (reliableFrames < minReliableFrames) {
        debugPrint('FlexWell: session too short (${reliableFrames} < '
            '${minReliableFrames} frames) -- nothing saved.');
        return newlyUnlocked;
      }

      final sessions = await _userCollection('sessions');
      if (sessions == null) {
        debugPrint('FlexWell: no signed-in user -- session NOT saved.');
        return newlyUnlocked;
      }

      // Sanitise inputs so bad values never reach Firestore or the rules below.
      final safeAccuracy = accuracy.clamp(0, 100).toInt();
      final safeReps = reps < 0 ? 0 : reps;
      final safeHold = longestHold < 0 ? 0 : longestHold;
      final safePerfect = perfectReps.clamp(0, safeReps).toInt();

      final now = DateTime.now();
      final todayKey = _dayKey(now);

      // Not awaited: Firestore only completes writes once the server
      // acknowledges them, which would stall while offline.
      unawaited(sessions.add({
        'exercise': exercise,
        'accuracy': safeAccuracy,
        'reps': safeReps,
        'longestHold': safeHold,
        'perfectReps': safePerfect,
        'dayKey': todayKey,
        'createdAt': FieldValue.serverTimestamp(),
      }).then((_) {}, onError: (e) => debugPrint('Saving session failed: $e')));

      Future<void> tryUnlock(String id) async {
        if (await unlockAchievement(id)) newlyUnlocked.add(id);
      }

      // Per-session achievements
      await tryUnlock('first_milestone');
      if (exercise == 'Plank' && safeHold >= 60) await tryUnlock('iron_core');
      if (exercise == 'Squat' && safeAccuracy > 90) await tryUnlock('form_master');
      // Every completed rep in the session stayed flawless throughout its
      // lifecycle (CameraScreen resets `_currentRepIsFlawless` per rep and
      // only counts a rep as perfect if form never broke while it was in
      // progress).
      if (safeReps >= minRepsForFlawlessAchievement && safePerfect == safeReps) {
        await tryUnlock('flawless_form');
      }

      // History-based achievements. The current session is added locally so
      // we don't depend on the write above having landed yet.
      final exercises = <String>{exercise};
      final dayKeys = <String>{todayKey};
      try {
        final history = await sessions.get().timeout(_readTimeout);
        for (final doc in history.docs) {
          final data = doc.data();
          final ex = data['exercise'];
          final day = data['dayKey'];
          if (ex is String) exercises.add(ex);
          if (day is String) dayKeys.add(day);
        }
      } catch (e) {
        debugPrint('Reading session history failed: $e');
      }

      if (exercises.length >= 6) await tryUnlock('gym_warrior');
      if (_hasConsecutiveDays(dayKeys, 3)) await tryUnlock('determination');
    } catch (e) {
      debugPrint('recordSession failed: $e');
    }
    return newlyUnlocked;
  }

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDay(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime.utc(y, m, d); // UTC avoids DST skewing day differences
  }

  static bool _hasConsecutiveDays(Set<String> dayKeys, int n) {
    final days = dayKeys.map(_parseDay).whereType<DateTime>().toList()..sort();
    if (days.length < n) return false;
    var run = 1;
    for (var i = 1; i < days.length; i++) {
      run = days[i].difference(days[i - 1]).inDays == 1 ? run + 1 : 1;
      if (run >= n) return true;
    }
    return false;
  }
}