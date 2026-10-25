import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flexwell_flutter/app_colors.dart';
import 'package:flexwell_flutter/dashboard_screen.dart';

void main() {
  testWidgets('dashboard leads with exercise selection and scan actions', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: DashboardScreen()));

    expect(find.text('FlexWell'), findsOneWidget);
    expect(find.text('Choose an exercise'), findsOneWidget);
    expect(
      find.text('Choose a movement to start a live form scan.'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      find.text('Start scan').first,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Start scan'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scan tiles fit a narrow screen with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: const DashboardScreen(),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Start scan').first,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard surfaces stay legible in both themes', (tester) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Theme(
            data: ThemeData(brightness: brightness),
            child: const DashboardScreen(),
          ),
        ),
      );

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(
        scaffold.backgroundColor,
        brightness == Brightness.dark
            ? AppColors.darkBackground
            : AppColors.lightBackground,
      );
      expect(
        tester.widget<Text>(find.text('Choose an exercise')).style?.color,
        Colors.white,
      );
      expect(tester.takeException(), isNull);
    }
  });
}
