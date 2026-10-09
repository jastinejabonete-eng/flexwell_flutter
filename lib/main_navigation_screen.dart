import 'package:flutter/material.dart';
import 'dashboard_screen.dart';
import 'app_colors.dart';
import 'tutorials_screen.dart';
import 'achievements_screen.dart';
import 'user_manual_screen.dart'; // <--- Import User Manual
import 'settings_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    TutorialsScreen(),
    AchievementsScreen(),
    UserManualScreen(), // <--- Added Screen
    SettingsScreen(),
  ];

  final List<Map<String, dynamic>> _navItems = const [
    {'icon': Icons.fitness_center_rounded, 'label': 'Dashboard'},
    {'icon': Icons.school_rounded, 'label': 'Tutorials'},
    {'icon': Icons.emoji_events_rounded, 'label': 'Badges'},
    {'icon': Icons.menu_book_rounded, 'label': 'Manual'}, // <--- Added Nav Item
    {'icon': Icons.settings_rounded, 'label': 'Settings'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.navBarBackground,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(_navItems.length, (index) {
                final isSelected = _currentIndex == index;
                final item = _navItems[index];

                return GestureDetector(
                  onTap: () => setState(() => _currentIndex = index),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.navBarActivePill : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          item['icon'] as IconData,
                          size: 18,
                          color: isSelected
                              ? AppColors.accent // Volt green active highlight
                              : AppColors.navBarInactive,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item['label'] as String,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected
                                ? AppColors.accent
                                : AppColors.navBarInactive,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}