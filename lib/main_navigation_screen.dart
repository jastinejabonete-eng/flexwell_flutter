import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import 'tutorials_screen.dart';
import 'achievements_screen.dart';
import 'user_manual_screen.dart'; // <--- Import User Manual
import 'settings_screen.dart';
import 'onboarding_service.dart';
import 'onboarding_tour_overlay.dart';
import 'onboarding_tour_steps.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  int? _tourStepIndex;
  bool _savingTour = false;
  final GlobalKey _tourRootKey = GlobalKey(debugLabel: 'tour-overlay-root');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showFirstRunTour();
    });
  }

  Future<void> _showFirstRunTour() async {
    if (await OnboardingService.hasCompletedTour() || !mounted) return;
    _startTour();
  }

  void _startTour() {
    setState(() {
      _currentIndex = OnboardingTourSteps.all.first.screenIndex;
      _tourStepIndex = 0;
    });
  }

  void _setTourStep(int index) {
    setState(() {
      _tourStepIndex = index;
      _currentIndex = OnboardingTourSteps.all[index].screenIndex;
    });
  }

  Future<void> _finishTour() async {
    if (_savingTour) return;
    setState(() => _savingTour = true);
    await OnboardingService.markTourCompleted();
    if (!mounted) return;
    setState(() {
      _tourStepIndex = null;
      _savingTour = false;
    });
  }

  void _selectTab(int index) {
    setState(() {
      _currentIndex = index;
      if (_tourStepIndex != null) {
        final matchingStep = OnboardingTourSteps.all.indexWhere(
          (step) => step.screenIndex == index,
        );
        if (matchingStep >= 0) _tourStepIndex = matchingStep;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const DashboardScreen(),
      const TutorialsScreen(),
      const AchievementsScreen(),
      const UserManualScreen(),
      SettingsScreen(onReplayTour: _startTour),
    ];
    final tourIndex = _tourStepIndex;
    final destinations = [
      (
        label: 'Dashboard',
        icon: Icons.fitness_center_rounded,
        selectedIcon: Icons.fitness_center,
      ),
      (
        label: 'Tutorials',
        icon: Icons.school_outlined,
        selectedIcon: Icons.school_rounded,
      ),
      (
        label: 'Badges',
        icon: Icons.emoji_events_outlined,
        selectedIcon: Icons.emoji_events_rounded,
      ),
      (
        label: 'Manual',
        icon: Icons.menu_book_outlined,
        selectedIcon: Icons.menu_book_rounded,
      ),
      (
        label: 'Settings',
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
      ),
    ];

    return Stack(
      key: _tourRootKey,
      fit: StackFit.expand,
      children: [
        Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final useRail = constraints.maxWidth >= 600;
              final content = IndexedStack(
                index: _currentIndex,
                children: screens,
              );

              if (!useRail) {
                // Account for the bottom NavigationBar so GridView contents
                // don't get cut off behind the last row of cards.
                final bottomPadding = MediaQuery.paddingOf(context).bottom +
                    kBottomNavigationBarHeight;
                return Padding(padding: EdgeInsets.only(bottom: bottomPadding), child: content);
              }

              return Row(
                children: [
                  NavigationRail(
                    selectedIndex: _currentIndex,
                    labelType: NavigationRailLabelType.all,
                    onDestinationSelected: _selectTab,
                    destinations: [
                      for (final destination in destinations)
                        NavigationRailDestination(
                          icon: Icon(destination.icon),
                          selectedIcon: Icon(destination.selectedIcon),
                          label: Text(destination.label),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              );
            },
          ),
          bottomNavigationBar: MediaQuery.sizeOf(context).width >= 600
              ? null
              : NavigationBar(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: _selectTab,
                  destinations: [
                    for (final destination in destinations)
                      NavigationDestination(
                        icon: Icon(destination.icon),
                        selectedIcon: Icon(destination.selectedIcon),
                        label: destination.label,
                      ),
                  ],
                ),
        ),
        if (tourIndex != null)
          Positioned.fill(
            child: OnboardingTourOverlay(
              overlayKey: _tourRootKey,
              step: OnboardingTourSteps.all[tourIndex],
              stepIndex: tourIndex,
              totalSteps: OnboardingTourSteps.all.length,
              isSaving: _savingTour,
              onPrevious: () {
                if (tourIndex > 0) _setTourStep(tourIndex - 1);
              },
              onNext: () {
                if (tourIndex == OnboardingTourSteps.all.length - 1) {
                  _finishTour();
                } else {
                  _setTourStep(tourIndex + 1);
                }
              },
              onSkip: _finishTour,
            ),
          ),
      ],
    );
  }
}
