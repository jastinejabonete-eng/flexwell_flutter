import 'package:flutter/material.dart';

class OnboardingTourAnchors {
  static final dashboardExercises = GlobalKey(debugLabel: 'tour-dashboard');
  static final dashboardSearch = GlobalKey(debugLabel: 'tour-search');
  static final tutorials = GlobalKey(debugLabel: 'tour-tutorials');
  static final manualQuickStart = GlobalKey(debugLabel: 'tour-manual');
  static final achievements = GlobalKey(debugLabel: 'tour-achievements');
  static final settings = GlobalKey(debugLabel: 'tour-settings');
}

class OnboardingTourStep {
  final int screenIndex;
  final GlobalKey targetKey;
  final String title;
  final String description;
  final IconData icon;

  const OnboardingTourStep({
    required this.screenIndex,
    required this.targetKey,
    required this.title,
    required this.description,
    required this.icon,
  });
}

class OnboardingTourSteps {
  static final List<OnboardingTourStep> all = List.unmodifiable([
    OnboardingTourStep(
      screenIndex: 0,
      targetKey: OnboardingTourAnchors.dashboardExercises,
      title: 'Choose a workout',
      description:
          'Choose an exercise for live form feedback. The setup guide shows '
          'the camera angle and joints to keep in frame.',
      icon: Icons.fitness_center_rounded,
    ),
    OnboardingTourStep(
      screenIndex: 0,
      targetKey: OnboardingTourAnchors.dashboardSearch,
      title: 'Find the right exercise',
      description:
          'Search by exercise or muscle, or filter by movement type and '
          'training area.',
      icon: Icons.search_rounded,
    ),
    OnboardingTourStep(
      screenIndex: 1,
      targetKey: OnboardingTourAnchors.tutorials,
      title: 'Learn the movement',
      description:
          'Watch a demo before you scan. Each guide also explains the camera '
          'setup.',
      icon: Icons.school_rounded,
    ),
    OnboardingTourStep(
      screenIndex: 3,
      targetKey: OnboardingTourAnchors.manualQuickStart,
      title: 'Understand your scan',
      description:
          'Use the suggested angle and keep required joints in frame. Follow '
          'the skeleton feedback, then review your score, reps, or hold time.',
      icon: Icons.accessibility_new_rounded,
    ),
    OnboardingTourStep(
      screenIndex: 2,
      targetKey: OnboardingTourAnchors.achievements,
      title: 'See your progress',
      description:
          'Workouts build your streak and unlock milestones. Find your earned '
          'badges here.',
      icon: Icons.emoji_events_rounded,
    ),
    OnboardingTourStep(
      screenIndex: 4,
      targetKey: OnboardingTourAnchors.settings,
      title: 'Make FlexWell yours',
      description:
          'Change the light or dark theme here. Replay this guided tour from '
          'Settings anytime.',
      icon: Icons.settings_rounded,
    ),
  ]);
}
