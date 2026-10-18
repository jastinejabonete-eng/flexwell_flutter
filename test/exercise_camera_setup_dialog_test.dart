import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flexwell_flutter/exercise_camera_setup_dialog.dart';

void main() {
  testWidgets(
    'camera setup dialog explains exercise-specific view and joints',
    (tester) async {
      bool? shouldStart;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  shouldStart = await showExerciseCameraSetup(context, 'Plank');
                },
                child: const Text('Open setup'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open setup'));
      await tester.pumpAndSettle();
      expect(find.text('Plank camera setup'), findsOneWidget);
      expect(find.text('Left side view'), findsOneWidget);
      expect(
        find.textContaining('shoulder, elbow, hip and ankle'),
        findsOneWidget,
      );
      expect(find.text('This scan tracks your hold time.'), findsOneWidget);

      await tester.tap(find.text('Continue to camera'));
      await tester.pumpAndSettle();
      expect(shouldStart, isTrue);
    },
  );
}
