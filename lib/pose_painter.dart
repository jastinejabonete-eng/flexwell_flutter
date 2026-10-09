import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PosePainter extends CustomPainter {
  final Pose? pose;
  final bool isCorrect;

  /// True when form can't be judged (unreliable landmarks / calibrating):
  /// draws the skeleton orange instead of red or green.
  final bool isNeutral;
  final Size imageSize;

  /// The front-camera preview is mirrored, but ML Kit landmark coordinates are
  /// not. When true, x is flipped so the skeleton lines up with the preview.
  final bool isFrontCamera;

  /// Hide hips, knees, ankles and feet (and every line touching them).
  ///
  /// In Pull-Up the legs are out of view, so ML Kit guesses those joints and
  /// they pile up on the chest. The analysis doesn't use them, so they are
  /// simply not drawn. Push-Up is filmed from the side and its body-line
  /// angle (shoulder-hip-ankle) needs the hips and ankles, so it draws them.
  final bool hideLowerBody;

  /// Landmarks the current exercise's analysis needs. If any of them is
  /// missing or below [minLikelihood], nothing is drawn (no partial skeleton).
  /// Null = always draw.
  final Set<PoseLandmarkType>? requiredLandmarks;

  /// Same reliability cut-off the analyzer uses (PoseAnalyzer._reliable).
  static const double minLikelihood = 0.6;

  PosePainter({
    required this.pose,
    required this.isCorrect,
    required this.imageSize,
    this.isFrontCamera = false,
    this.isNeutral = false,
    this.hideLowerBody = false,
    this.requiredLandmarks,
  });

  /// Must mirror the `required` lists in PoseAnalyzer.analyze().
  static Set<PoseLandmarkType> requiredFor(String exercise) {
    switch (exercise) {
      case 'Squat':
        return {
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.leftHip,
          PoseLandmarkType.leftKnee,
          PoseLandmarkType.leftAnkle,
        };
      case 'Push-Up':
        return {
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.leftElbow,
          PoseLandmarkType.leftWrist,
          PoseLandmarkType.leftHip,
          PoseLandmarkType.leftAnkle,
        };
      case 'Pull-Up':
        return {
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.leftElbow,
          PoseLandmarkType.rightElbow,
        };
      default: // Lunge, Plank, Side Plank
        return {
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.leftHip,
          PoseLandmarkType.leftKnee,
          PoseLandmarkType.leftAnkle,
        };
    }
  }

  bool _hasRequiredLandmarks(Pose pose) {
    final required = requiredLandmarks;
    if (required == null) return true;
    for (final type in required) {
      final lm = pose.landmarks[type];
      if (lm == null || lm.likelihood < minLikelihood) return false;
    }
    return true;
  }

  static const connections = [
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
    [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
    [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
    [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
    [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
    [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
    [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
    [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
    [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
  ];

  static const _lowerBody = {
    PoseLandmarkType.leftHip,
    PoseLandmarkType.rightHip,
    PoseLandmarkType.leftKnee,
    PoseLandmarkType.rightKnee,
    PoseLandmarkType.leftAnkle,
    PoseLandmarkType.rightAnkle,
    PoseLandmarkType.leftHeel,
    PoseLandmarkType.rightHeel,
    PoseLandmarkType.leftFootIndex,
    PoseLandmarkType.rightFootIndex,
  };

  /// Exercises whose analysis doesn't use the lower body.
  static bool hidesLowerBody(String exercise) =>
      exercise == 'Pull-Up';

  @override
  void paint(Canvas canvas, Size size) {
    final currentPose = pose;
    if (currentPose == null) return;
    // Zero/invalid sizes would make the scale Infinity or NaN.
    if (imageSize.isEmpty ||
        !imageSize.width.isFinite ||
        !imageSize.height.isFinite ||
        size.isEmpty) {
      return;
    }
    // Incomplete skeleton for this exercise: draw nothing.
    if (!_hasRequiredLandmarks(currentPose)) return;
    final color = isNeutral ? Colors.orange : (isCorrect ? Colors.green : Colors.red);

    // Bones: drawn as one batch of line segments (butt caps, width 4, exactly
    // like the previous per-line drawLine calls).
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 4;
    // Joints: a round-capped point of width 12 is a filled circle of radius 6,
    // identical to the previous drawCircle(…, 6, …), but drawn in one call.
    final pointPaint = Paint()
      ..color = color
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    // Mirror the preview's layout EXACTLY (see camera_screen.dart):
    //   previewAspectRatio = 1 / camera.aspectRatio
    //   a child is laid out at that aspect ratio inside the screen
    //   (AspectRatio picks the box that fits the screen), then uniformly
    //   scaled by scale = max(screenAR/previewAR, previewAR/screenAR) about
    //   the screen centre. Using any other scale expression (e.g. the old
    //   max(size.w/imageSize.w, size.h/imageSize.h)) makes the skeleton drift
    //   off the body whenever the sensor and screen aspects differ.
    final previewAspectRatio = imageSize.width / imageSize.height;
    final screenAR = size.width / size.height;
    var scale = screenAR / previewAspectRatio;
    if (scale < 1) scale = 1 / scale;

    // Size of the laid-out preview box (the one that fits the screen).
    double laidW, laidH;
    if (imageSize.width / imageSize.height > screenAR) {
      laidW = size.width;
      laidH = size.width / previewAspectRatio;
    } else {
      laidH = size.height;
      laidW = size.height * previewAspectRatio;
    }
    final offsetX = (size.width - laidW) / 2;
    final offsetY = (size.height - laidH) / 2;

    Offset mapPoint(PoseLandmark landmark) {
      var x = landmark.x * scale + offsetX;
      // Mirror in SCREEN space: x -> W - x. Flip the raw landmark BEFORE
      // applying scale+offset so the offset keeps its sign:
      //   x = size.width - landmark.x * scale - offsetX.
      if (isFrontCamera) {
        x = size.width - landmark.x * scale - offsetX;
      }
      return Offset(x, landmark.y * scale + offsetY);
    }

    bool visible(PoseLandmark? lm) {
      if (lm == null) return false;
      return !(hideLowerBody && _lowerBody.contains(lm.type));
    }

    final segments = <Offset>[];
    for (final pair in connections) {
      final a = currentPose.landmarks[pair[0]];
      final b = currentPose.landmarks[pair[1]];
      if (visible(a) && visible(b)) {
        segments.add(mapPoint(a!));
        segments.add(mapPoint(b!));
      }
    }
    if (segments.isNotEmpty) {
      canvas.drawPoints(ui.PointMode.lines, segments, linePaint);
    }

    final joints = <Offset>[];
    for (final landmark in currentPose.landmarks.values) {
      if (visible(landmark)) joints.add(mapPoint(landmark));
    }
    if (joints.isNotEmpty) {
      canvas.drawPoints(ui.PointMode.points, joints, pointPaint);
    }
  }

  // Repaint only when something visible changed. A new Pose arrives every
  // processed frame, so the skeleton still updates each frame; the difference
  // is that identical repeats (e.g. no person in frame) are skipped.
  @override
  bool shouldRepaint(covariant PosePainter old) =>
      old.pose != pose ||
      old.isCorrect != isCorrect ||
      old.isNeutral != isNeutral ||
      old.imageSize != imageSize ||
      old.isFrontCamera != isFrontCamera ||
      old.hideLowerBody != hideLowerBody ||
      old.requiredLandmarks != requiredLandmarks;
}