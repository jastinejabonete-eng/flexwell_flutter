import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:flexwell_flutter/knn_core.dart';
import 'package:flexwell_flutter/pose_analyzer.dart';

Pose buildPose(
  Map<PoseLandmarkType, List<double>> points, {
  Set<PoseLandmarkType> lowConfidence = const {},
  Map<PoseLandmarkType, double> likelihoods = const {},
}) {
  return Pose(
    landmarks: {
      for (final entry in points.entries)
        entry.key: PoseLandmark(
          type: entry.key,
          x: entry.value[0],
          y: entry.value[1],
          z: 0,
          likelihood:
              likelihoods[entry.key] ??
              (lowConfidence.contains(entry.key) ? 0.2 : 0.95),
        ),
    },
  );
}

const plankPose = {
  PoseLandmarkType.leftShoulder: [100.0, 100.0],
  PoseLandmarkType.leftHip: [200.0, 100.0],
  PoseLandmarkType.leftKnee: [250.0, 100.0],
  PoseLandmarkType.leftAnkle: [300.0, 100.0],
  PoseLandmarkType.leftElbow: [130.0, 105.0],
};

Pose pullUpPose({double shoulderY = 100, double hipY = 220}) => buildPose({
  PoseLandmarkType.leftShoulder: [100, shoulderY],
  PoseLandmarkType.rightShoulder: [120, shoulderY],
  PoseLandmarkType.leftElbow: [90, shoulderY + 50],
  PoseLandmarkType.rightElbow: [130, shoulderY + 50],
  PoseLandmarkType.leftWrist: [80, shoulderY + 100],
  PoseLandmarkType.rightWrist: [140, shoulderY + 100],
  PoseLandmarkType.leftHip: [105, hipY],
  PoseLandmarkType.rightHip: [115, hipY],
});

class _TestClock {
  DateTime current = DateTime.utc(2025);

  DateTime call() => current;

  void advance([Duration duration = const Duration(milliseconds: 100)]) {
    current = current.add(duration);
  }
}

void main() {
  group('PoseAnalyzer reliability and calibration', () {
    test('Plank requires a visible, reliable left elbow', () async {
      final analyzer = PoseAnalyzer();

      final missingElbow = await analyzer.analyze(
        'Plank',
        buildPose({...plankPose}..remove(PoseLandmarkType.leftElbow)),
      );
      expect(missingElbow.landmarksReliable, isFalse);

      final lowConfidenceElbow = await analyzer.analyze(
        'Side Plank',
        buildPose(plankPose, lowConfidence: {PoseLandmarkType.leftElbow}),
      );
      expect(lowConfidenceElbow.landmarksReliable, isFalse);
    });

    test('ML Kit landmark likelihood cutoff includes exactly 0.6', () async {
      final analyzer = PoseAnalyzer(
        classifier: (_, _) async => const KnnVerdict.correct(),
      );

      final atCutoff = await analyzer.analyze(
        'Plank',
        buildPose(plankPose, likelihoods: {PoseLandmarkType.leftElbow: 0.6}),
      );
      final belowCutoff = await analyzer.analyze(
        'Plank',
        buildPose(plankPose, likelihoods: {PoseLandmarkType.leftElbow: 0.59}),
      );

      expect(atCutoff.landmarksReliable, isTrue);
      expect(belowCutoff.landmarksReliable, isFalse);
    });

    test('calibration requires a stable one-second window', () async {
      final clock = _TestClock();
      final analyzer = PoseAnalyzer(clock: clock.call);

      final invalidStart = await analyzer.analyze(
        'Pull-Up',
        pullUpPose(shoulderY: 220, hipY: 220),
      );
      expect(
        invalidStart.message,
        'Hang from the bar with your arms straight to start',
      );

      for (var frame = 0; frame < 10; frame++) {
        final result = await _analyzePullUpFrame(
          analyzer,
          clock,
          shoulderY: frame.isEven ? 120 : 100,
        );
        expect(result.message, 'Calibrating - hold your starting position');
      }

      for (var frame = 0; frame < 10; frame++) {
        final result = await _analyzePullUpFrame(
          analyzer,
          clock,
          shoulderY: 120,
        );
        expect(result.message, 'Calibrating - hold your starting position');
      }

      final calibrated = await _analyzePullUpFrame(
        analyzer,
        clock,
        shoulderY: 120,
      );
      expect(calibrated.message, 'Stand ready -- start your rep');
    });

    test(
      'calibration rejects missing or low-confidence bilateral hips',
      () async {
        final analyzer = PoseAnalyzer();
        final missingHip = pullUpPose().landmarks
          ..remove(PoseLandmarkType.rightHip);
        final lowConfidenceHip = buildPose(
          {
            for (final entry in pullUpPose().landmarks.entries)
              entry.key: [entry.value.x, entry.value.y],
          },
          lowConfidence: {PoseLandmarkType.leftHip},
        );

        for (final pose in [Pose(landmarks: missingHip), lowConfidenceHip]) {
          final result = await analyzer.analyze('Pull-Up', pose);
          expect(result.landmarksReliable, isFalse);
          expect(result.message, contains('Can\'t see you clearly'));
        }
      },
    );

    test('rep engagement is gated by elapsed time, not frame count', () async {
      final clock = _TestClock();
      var classifications = 0;
      final analyzer = PoseAnalyzer(
        clock: clock.call,
        classifier: (_, _) async {
          classifications++;
          return const KnnVerdict.correct();
        },
      );
      await _calibratePullUp(analyzer, clock);

      await _analyzePullUpFrame(analyzer, clock, shoulderY: 50);
      await _analyzePullUpFrame(analyzer, clock, shoulderY: 100);
      expect(classifications, 0);
    });

    test(
      'peak dwell commits after elapsed time despite EMA settling',
      () async {
        final clock = _TestClock();
        var classifications = 0;
        final analyzer = PoseAnalyzer(
          clock: clock.call,
          classifier: (_, _) async {
            classifications++;
            return const KnnVerdict.correct();
          },
        );
        await _calibratePullUp(analyzer, clock);

        AnalysisResult? result;
        for (var frame = 0; frame < 12; frame++) {
          result = await _analyzePullUpFrame(analyzer, clock, shoulderY: 50);
        }

        expect(classifications, 1);
        expect(result!.message, 'Good form');
      },
    );

    test(
      'rep OOD is reported as unfamiliar form, not unavailable model',
      () async {
        final clock = _TestClock();
        final analyzer = PoseAnalyzer(
          clock: clock.call,
          classifier: (_, _) async => const KnnVerdict.outOfDistribution(),
        );
        await _calibratePullUp(analyzer, clock);

        final result = await _drivePullUpThroughReversal(analyzer, clock);
        expect(result.message, 'Unfamiliar form - try to match the guide');
        expect(result.landmarksReliable, isFalse);
      },
    );

    test(
      'incorrect and OOD feedback holds for one second after rep end',
      () async {
        final clock = _TestClock();
        final analyzer = PoseAnalyzer(
          clock: clock.call,
          classifier: (_, _) async => const KnnVerdict.outOfDistribution(),
        );
        await _calibratePullUp(analyzer, clock);
        await _commitPullUpByReversal(analyzer, clock);

        final held = await _analyzePullUpFrame(analyzer, clock);
        expect(held.message, 'Unfamiliar form - try to match the guide');
        clock.advance(const Duration(milliseconds: 1100));
        final expired = await _analyzePullUpFrame(analyzer, clock);
        expect(expired.message, 'Stand ready -- start your rep');
      },
    );

    test('unavailable rep model keeps the unavailable message', () async {
      final clock = _TestClock();
      final analyzer = PoseAnalyzer(
        clock: clock.call,
        classifier: (_, _) async => const KnnVerdict.unavailable(),
      );
      await _calibratePullUp(analyzer, clock);

      final result = await _drivePullUpThroughReversal(analyzer, clock);
      expect(result.message, 'Form model unavailable');
    });
  });
}

Future<AnalysisResult> _analyzePullUpFrame(
  PoseAnalyzer analyzer,
  _TestClock clock, {
  double shoulderY = 100,
}) async {
  clock.advance();
  return analyzer.analyze('Pull-Up', pullUpPose(shoulderY: shoulderY));
}

Future<void> _calibratePullUp(PoseAnalyzer analyzer, _TestClock clock) async {
  for (var frame = 0; frame < 11; frame++) {
    await _analyzePullUpFrame(analyzer, clock);
  }
}

Future<AnalysisResult> _drivePullUpThroughReversal(
  PoseAnalyzer analyzer,
  _TestClock clock,
) async {
  AnalysisResult? result;
  for (var frame = 0; frame < 20; frame++) {
    result = await _analyzePullUpFrame(analyzer, clock, shoulderY: 50);
  }
  for (var frame = 0; frame < 8; frame++) {
    result = await _analyzePullUpFrame(analyzer, clock);
    if (result.message == 'Unfamiliar form - try to match the guide' ||
        result.message == 'Form model unavailable') {
      return result;
    }
  }
  return result!;
}

Future<void> _commitPullUpByReversal(
  PoseAnalyzer analyzer,
  _TestClock clock,
) async {
  for (var frame = 0; frame < 5; frame++) {
    await _analyzePullUpFrame(analyzer, clock, shoulderY: 50);
  }
  await _analyzePullUpFrame(analyzer, clock);
}
