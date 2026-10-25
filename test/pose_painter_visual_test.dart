// Visual/golden test of the real PosePainter, driven with real poses.
// Reads pixel colours back out of the rendered widget, so it verifies what is
// actually drawn, not just that the painter ran.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'package:flexwell_flutter/pose_painter.dart';

// The painter uses Flutter's Colors.green / Colors.red / Colors.orange.
// Match the SAME values it draws, otherwise this test fails for a reason
// that has nothing to do with the app (Colors.green is 0xFF4CAF50, not
// 0x00FF00).
const kGreen = Color(0xFF4CAF50); // Colors.green
const kRed = Color(0xFFF44336); // Colors.red
const kOrange = Color(0xFFFFA500); // Colors.orange

// Build a Pose from a simple joint map. x/y are in "image pixels"; the test
// uses a 480x640 frame so mapPoint() has something real to scale by.
Pose buildPose(
  Map<PoseLandmarkType, List<double>> pts, {
  Set<PoseLandmarkType> lowConfidence = const {},
  Map<PoseLandmarkType, double> likelihoods = const {},
}) {
  final landmarks = <PoseLandmarkType, PoseLandmark>{};
  pts.forEach((type, xy) {
    landmarks[type] = PoseLandmark(
      type: type,
      x: xy[0],
      y: xy[1],
      z: 0.0,
      likelihood:
          likelihoods[type] ?? (lowConfidence.contains(type) ? 0.2 : 0.95),
    );
  });
  return Pose(landmarks: landmarks);
}

const fullBody = <PoseLandmarkType, List<double>>{
  PoseLandmarkType.leftShoulder: [200, 200],
  PoseLandmarkType.rightShoulder: [280, 200],
  PoseLandmarkType.leftElbow: [190, 280],
  PoseLandmarkType.rightElbow: [290, 280],
  PoseLandmarkType.leftWrist: [185, 350],
  PoseLandmarkType.rightWrist: [295, 350],
  PoseLandmarkType.leftHip: [210, 380],
  PoseLandmarkType.rightHip: [270, 380],
  PoseLandmarkType.leftKnee: [205, 480],
  PoseLandmarkType.rightKnee: [275, 480],
  PoseLandmarkType.leftAnkle: [200, 580],
  PoseLandmarkType.rightAnkle: [280, 580],
};

Future<ui.Image> render(PosePainter painter, Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, size);
  final picture = recorder.endRecording();
  return picture.toImage(size.width.toInt(), size.height.toInt());
}

/// Count pixels that are "close to" a target colour, ignoring alpha.
Future<int> countColour(ui.Image img, Color target, {int tol = 60}) async {
  final data = await img.toByteData();
  if (data == null) return 0;
  final b = data.buffer.asUint8List();
  final targetRed = (target.r * 255).round();
  final targetGreen = (target.g * 255).round();
  final targetBlue = (target.b * 255).round();
  int n = 0;
  for (int i = 0; i < b.length; i += 4) {
    final r = b[i], g = b[i + 1], bl = b[i + 2];
    if ((r - targetRed).abs() <= tol &&
        (g - targetGreen).abs() <= tol &&
        (bl - targetBlue).abs() <= tol) {
      n++;
    }
  }
  return n;
}

Future<bool> hasColourNear(
  ui.Image img,
  Color target,
  Offset center, {
  int radius = 8,
  int tol = 40,
}) async {
  final data = await img.toByteData();
  if (data == null) return false;
  final bytes = data.buffer.asUint8List();
  final targetRed = (target.r * 255).round();
  final targetGreen = (target.g * 255).round();
  final targetBlue = (target.b * 255).round();
  for (
    var y = center.dy.toInt() - radius;
    y <= center.dy.toInt() + radius;
    y++
  ) {
    for (
      var x = center.dx.toInt() - radius;
      x <= center.dx.toInt() + radius;
      x++
    ) {
      final i = (y * img.width + x) * 4;
      final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2];
      if ((r - targetRed).abs() <= tol &&
          (g - targetGreen).abs() <= tol &&
          (b - targetBlue).abs() <= tol) {
        return true;
      }
    }
  }
  return false;
}

void main() {
  const size = Size(480, 640);

  test('correct form draws a GREEN skeleton', () async {
    final img = await render(
      PosePainter(
        pose: buildPose(fullBody),
        isCorrect: true,
        imageSize: const Size(480, 640),
        requiredLandmarks: PosePainter.requiredFor('Squat'),
      ),
      size,
    );
    final green = await countColour(img, kGreen);
    debugPrint('GREEN_PIXELS=$green');
    expect(
      green,
      greaterThan(0),
      reason: 'correct form must draw green joints',
    );
  });

  test('incorrect form draws a RED skeleton', () async {
    final img = await render(
      PosePainter(
        pose: buildPose(fullBody),
        isCorrect: false,
        imageSize: const Size(480, 640),
        requiredLandmarks: PosePainter.requiredFor('Squat'),
      ),
      size,
    );
    final red = await countColour(img, kRed);
    debugPrint('RED_PIXELS=$red');
    expect(red, greaterThan(0), reason: 'incorrect form must draw red joints');
  });

  test('painter uses the analyzer likelihood cutoff', () async {
    final atCutoff = await render(
      PosePainter(
        pose: buildPose(
          fullBody,
          likelihoods: {PoseLandmarkType.leftKnee: 0.6},
        ),
        isCorrect: true,
        imageSize: const Size(480, 640),
        requiredLandmarks: PosePainter.requiredFor('Squat'),
      ),
      size,
    );
    final belowCutoff = await render(
      PosePainter(
        pose: buildPose(
          fullBody,
          likelihoods: {PoseLandmarkType.leftKnee: 0.59},
        ),
        isCorrect: true,
        imageSize: const Size(480, 640),
        requiredLandmarks: PosePainter.requiredFor('Squat'),
      ),
      size,
    );

    expect(await countColour(atCutoff, kGreen), greaterThan(0));
    expect(await countColour(belowCutoff, kGreen), 0);
  });

  test('neutral (cannot judge) draws ORANGE, never red or green', () async {
    final img = await render(
      PosePainter(
        pose: buildPose(fullBody),
        isCorrect: false,
        isNeutral: true,
        imageSize: const Size(480, 640),
        requiredLandmarks: PosePainter.requiredFor('Squat'),
      ),
      size,
    );
    // Tolerance 25 (not 60): Colors.orange (255,165,0) and Colors.red
    // (244,67,54) differ by 98 in green, but with tol=60 an anti-aliased
    // edge pixel blending orange toward red lands inside the red window and
    // reads as a false "red skeleton". 25 keeps orange edges out of red while
    // still tolerating normal edge blending.
    final orange = await countColour(img, kOrange, tol: 25);
    final red = await countColour(img, kRed, tol: 25);
    final green = await countColour(img, kGreen, tol: 25);
    debugPrint('ORANGE_PIXELS=$orange RED=$red GREEN=$green (tol=25)');
    expect(orange, greaterThan(0), reason: 'neutral must draw orange');
    expect(red, 0, reason: 'neutral must never draw red (no false "bad form")');
    expect(green, 0, reason: 'neutral must never draw green (no false "good")');
  });

  test(
    'missing required landmark draws NOTHING (no partial skeleton)',
    () async {
      final partial = Map<PoseLandmarkType, List<double>>.from(fullBody)
        ..remove(PoseLandmarkType.leftKnee); // Squat needs it
      final img = await render(
        PosePainter(
          pose: buildPose(partial),
          isCorrect: false,
          imageSize: const Size(480, 640),
          requiredLandmarks: PosePainter.requiredFor('Squat'),
        ),
        size,
      );
      final anyColour = await countColour(img, kRed, tol: 40);
      debugPrint('PARTIAL_PIXELS=$anyColour');
      expect(anyColour, 0, reason: 'incomplete skeleton must not be drawn');
    },
  );

  test('Plank skeleton requires its feature elbow', () {
    expect(
      PosePainter.requiredFor('Plank'),
      contains(PoseLandmarkType.leftElbow),
    );
    expect(
      PosePainter.requiredFor('Side Plank'),
      contains(PoseLandmarkType.leftElbow),
    );
  });

  test(
    'explicitly mirrored preview gets a mirrored skeleton overlay',
    () async {
      final singleJoint = buildPose({
        PoseLandmarkType.leftShoulder: [200, 200],
      });
      final unmirrored = await render(
        PosePainter(
          pose: singleJoint,
          isCorrect: true,
          imageSize: const Size(480, 640),
        ),
        size,
      );
      final mirrored = await render(
        PosePainter(
          pose: singleJoint,
          isCorrect: true,
          imageSize: const Size(480, 640),
          isFrontCamera: true,
        ),
        size,
      );

      expect(
        await hasColourNear(unmirrored, kGreen, const Offset(169, 200)),
        isTrue,
      );
      expect(
        await hasColourNear(mirrored, kGreen, const Offset(311, 200)),
        isTrue,
      );
    },
  );

  test(
    'low-confidence optional landmarks draw neither joint nor bones',
    () async {
      final pose = buildPose(
        fullBody,
        lowConfidence: {PoseLandmarkType.leftWrist},
      );
      final img = await render(
        PosePainter(
          pose: pose,
          isCorrect: true,
          imageSize: const Size(480, 640),
          requiredLandmarks: PosePainter.requiredFor('Squat'),
        ),
        size,
      );

      // With this test's aspect ratio, the left wrist maps to (142, 373).
      expect(
        await hasColourNear(img, kGreen, const Offset(142, 373)),
        isFalse,
        reason: 'low-confidence wrist should not be drawn as a joint or bone',
      );
    },
  );

  test('Pull-Up hides the lower body', () async {
    final painter = PosePainter(
      pose: buildPose(fullBody),
      isCorrect: true,
      imageSize: const Size(480, 640),
      hideLowerBody: PosePainter.hidesLowerBody('Pull-Up'),
      requiredLandmarks: PosePainter.requiredFor('Pull-Up'),
    );
    final img = await render(painter, size);
    final green = await countColour(img, kGreen);
    debugPrint('PULLUP_GREEN_PIXELS=$green');
    // Legs removed -> fewer pixels than the full-body Squat draw.
    final squatImg = await render(
      PosePainter(
        pose: buildPose(fullBody),
        isCorrect: true,
        imageSize: const Size(480, 640),
        requiredLandmarks: PosePainter.requiredFor('Squat'),
      ),
      size,
    );
    final squatGreen = await countColour(squatImg, kGreen);
    debugPrint('SQUAT_GREEN_PIXELS=$squatGreen');
    expect(green, greaterThan(0));
    expect(
      green,
      lessThan(squatGreen),
      reason: 'Pull-Up must draw fewer joints (legs hidden)',
    );
  });

  test(
    'skeleton is drawn inside the preview box (on-body, not off-screen)',
    () async {
      final img = await render(
        PosePainter(
          pose: buildPose(fullBody),
          isCorrect: true,
          imageSize: const Size(480, 640),
          requiredLandmarks: PosePainter.requiredFor('Squat'),
        ),
        size,
      );
      final data = await img.toByteData();
      final b = data!.buffer.asUint8List();
      final greenRed = (kGreen.r * 255).round();
      final greenGreen = (kGreen.g * 255).round();
      final greenBlue = (kGreen.b * 255).round();
      int minX = size.width.toInt(),
          maxX = 0,
          minY = size.height.toInt(),
          maxY = 0;
      int found = 0;
      for (int i = 0; i < b.length; i += 4) {
        final r = b[i], g = b[i + 1], bl = b[i + 2];
        final isGreen =
            (r - greenRed).abs() <= 60 &&
            (g - greenGreen).abs() <= 60 &&
            (bl - greenBlue).abs() <= 60;
        if (isGreen) {
          final px = (i ~/ 4) % size.width.toInt();
          final py = (i ~/ 4) ~/ size.width.toInt();
          if (px < minX) minX = px;
          if (px > maxX) maxX = px;
          if (py < minY) minY = py;
          if (py > maxY) maxY = py;
          found++;
        }
      }
      debugPrint('SKELETON_BBOX x=[$minX,$maxX] y=[$minY,$maxY] pixels=$found');
      expect(found, greaterThan(0));
      // Must be fully inside the canvas.
      expect(minX, greaterThanOrEqualTo(0));
      expect(maxX, lessThan(size.width.toInt()));
      expect(minY, greaterThanOrEqualTo(0));
      expect(maxY, lessThan(size.height.toInt()));
    },
  );
}
