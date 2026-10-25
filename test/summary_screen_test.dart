import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flexwell_flutter/summary_screen.dart';

void main() {
  testWidgets('summary explains when there is not enough tracked data', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SummaryScreen(
          exercise: 'Squat',
          accuracy: 0,
          reps: 0,
          longestHold: 0,
          isRepBased: true,
          hasSufficientData: false,
        ),
      ),
    );

    expect(find.text('Not enough data to score this session'), findsOneWidget);
    expect(
      find.text(
        'Stay in frame and keep moving so FlexWell can track your form.',
      ),
      findsOneWidget,
    );
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('summary shows accuracy when enough data exists', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SummaryScreen(
          exercise: 'Squat',
          accuracy: 82,
          reps: 3,
          longestHold: 0,
          isRepBased: true,
          hasSufficientData: true,
        ),
      ),
    );

    expect(find.text('82%'), findsOneWidget);
    expect(find.text('Accuracy'), findsOneWidget);
    expect(find.text('Not enough data to score this session'), findsNothing);
  });

  testWidgets('summary surfaces finalization warnings', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SummaryScreen(
          exercise: 'Squat',
          accuracy: 82,
          reps: 3,
          longestHold: 0,
          isRepBased: true,
          hasSufficientData: true,
          warningMessage: 'The unfinished rep could not be scored.',
        ),
      ),
    );

    expect(
      find.text('The unfinished rep could not be scored.'),
      findsOneWidget,
    );
  });
}
