import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flexwell_flutter/onboarding_service.dart';
import 'package:flexwell_flutter/onboarding_tour_overlay.dart';
import 'package:flexwell_flutter/onboarding_tour_steps.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('tour steps describe all app sections in navigation order', () {
    expect(OnboardingTourSteps.all, hasLength(6));
    expect(OnboardingTourSteps.all.map((step) => step.screenIndex), [
      0,
      0,
      1,
      3,
      2,
      4,
    ]);
  });

  testWidgets('spotlight callout advances and can be skipped', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _TourHarness()));
    await tester.pumpAndSettle();

    expect(find.text('Choose a workout'), findsOneWidget);
    expect(find.byKey(_TourHarness.targetKey), findsOneWidget);
    expect(find.byKey(const ValueKey('tour_next')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('tour_callout'))).height,
      lessThan(300),
    );

    await tester.tap(find.byKey(const ValueKey('tour_next')));
    await tester.pumpAndSettle();
    expect(find.text('Find the right exercise'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tour_skip')));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingTourOverlay), findsNothing);
    expect(await OnboardingService.hasCompletedTour(), isTrue);
  });

  testWidgets('spotlight fits narrow screens with enlarged text', (
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
        home: const _TourHarness(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Choose a workout'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('tour_callout'))).height,
      lessThan(400),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('tour_next')));
    await tester.pumpAndSettle();
    expect(find.text('Find the right exercise'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _TourHarness extends StatefulWidget {
  const _TourHarness();

  static final GlobalKey targetKey = GlobalKey(debugLabel: 'test-tour-target');
  static final GlobalKey rootKey = GlobalKey(debugLabel: 'test-tour-root');
  static final steps = [
    OnboardingTourStep(
      screenIndex: 0,
      targetKey: targetKey,
      title: 'Choose a workout',
      description: 'Select an exercise to get real-time form feedback.',
      icon: Icons.fitness_center_rounded,
    ),
    OnboardingTourStep(
      screenIndex: 0,
      targetKey: targetKey,
      title: 'Find the right exercise',
      description: 'Search and filter the exercise list.',
      icon: Icons.search_rounded,
    ),
  ];

  @override
  State<_TourHarness> createState() => _TourHarnessState();
}

class _TourHarnessState extends State<_TourHarness> {
  int? _stepIndex = 0;

  Future<void> _finish() async {
    await OnboardingService.markTourCompleted();
    if (mounted) setState(() => _stepIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    final stepIndex = _stepIndex;
    return Stack(
      key: _TourHarness.rootKey,
      fit: StackFit.expand,
      children: [
        Scaffold(
          body: Center(
            child: Container(
              key: _TourHarness.targetKey,
              padding: const EdgeInsets.all(16),
              child: const Text('Target feature'),
            ),
          ),
        ),
        if (stepIndex != null)
          Positioned.fill(
            child: OnboardingTourOverlay(
              overlayKey: _TourHarness.rootKey,
              step: _TourHarness.steps[stepIndex],
              stepIndex: stepIndex,
              totalSteps: _TourHarness.steps.length,
              isSaving: false,
              onPrevious: () => setState(() => _stepIndex = 0),
              onNext: () {
                if (stepIndex == _TourHarness.steps.length - 1) {
                  _finish();
                } else {
                  setState(() => _stepIndex = stepIndex + 1);
                }
              },
              onSkip: _finish,
            ),
          ),
      ],
    );
  }
}
