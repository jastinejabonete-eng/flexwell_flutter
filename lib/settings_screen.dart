import 'package:flutter/material.dart';

import 'main.dart';
import 'onboarding_tour_steps.dart';
import 'terms_screen.dart';

class SettingsScreen extends StatelessWidget {
  final VoidCallback? onReplayTour;

  const SettingsScreen({super.key, this.onReplayTour});

  Widget _leadingIcon(BuildContext context, IconData icon) {
    final color = Theme.of(context).colorScheme.primary;
    return Icon(icon, color: color);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text(
            'Personalize your training experience.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Card(
            key: OnboardingTourAnchors.settings,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: _leadingIcon(
                    context,
                    theme.brightness == Brightness.dark
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                  ),
                  title: const Text('Dark mode'),
                  subtitle: const Text('Choose a comfortable appearance'),
                  value: theme.brightness == Brightness.dark,
                  onChanged: (value) {
                    themeNotifier.value = value
                        ? ThemeMode.dark
                        : ThemeMode.light;
                  },
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  key: const ValueKey('settings_replay_tour'),
                  leading: _leadingIcon(context, Icons.explore_rounded),
                  title: const Text('Replay app tour'),
                  subtitle: const Text('Review camera setup and app features'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: onReplayTour,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: _leadingIcon(context, Icons.description_outlined),
                  title: const Text('Terms & Conditions'),
                  subtitle: const Text(
                    'Review FlexWell’s data and usage terms',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TermsScreen()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
