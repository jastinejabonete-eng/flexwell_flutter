import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flexwell_flutter/tutorials_screen.dart';

void main() {
  testWidgets('tutorial cards expose descriptive expandable controls', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    try {
      await tester.pumpWidget(const MaterialApp(home: TutorialsScreen()));

      expect(find.text('Learn the movement first'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('LOWER BODY STRENGTH'), 300);
      final controlFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Watch Squat tutorial video',
      );
      expect(controlFinder, findsOneWidget);

      final control = tester.getSemantics(controlFinder);
      final data = control.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isExpanded, Tristate.isFalse);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('tutorial cards fit narrow screens with enlarged text', (
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
        home: const TutorialsScreen(),
      ),
    );

    await tester.scrollUntilVisible(find.text('LOWER BODY STRENGTH'), 240);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Watch tutorial'), findsWidgets);
  });
}
