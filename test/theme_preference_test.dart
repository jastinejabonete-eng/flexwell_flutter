import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flexwell_flutter/theme_preference.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('uses dark mode when there is no saved preference', () async {
    expect(await ThemePreference.load(), ThemeMode.dark);
  });

  test('restores the selected light or dark mode', () async {
    await ThemePreference.save(ThemeMode.light);
    expect(await ThemePreference.load(), ThemeMode.light);

    await ThemePreference.save(ThemeMode.dark);
    expect(await ThemePreference.load(), ThemeMode.dark);
  });
}
