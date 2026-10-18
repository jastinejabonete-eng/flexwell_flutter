import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'form_smoother.dart';
import 'knn_core.dart';
import 'knn_worker.dart';
import 'pose_landmark_requirements.dart';

class AnalysisResult {
  final bool isCorrect;
  final String message;
  final double
  repSignal; // meaning differs by exercise -- see class comment below
  final bool landmarksReliable;

  /// Landmark-smoothed copy of the input pose, for on-screen drawing only
  /// (classification uses the raw pose). Null when there was no pose.
  final Pose? smoothedPose;
  AnalysisResult(
    this.isCorrect,
    this.message,
    this.repSignal, {
    this.landmarksReliable = true,
    this.smoothedPose,
  });
}

class _Point2D {
  final double x;
  final double y;
  const _Point2D(this.x, this.y);
}

/// Mutable accumulator for the landmark EMA (kept separate from the immutable
/// [_Point2D] used for feature maths).
class _Point3D {
  double x;
  double y;
  _Point3D(this.x, this.y);
}

/// Feature meaning by exercise (must match the training data in
/// assets/knn_training_data.json):
///   Squat       (left):  [left_knee_angle (hip-knee-ankle), torso_lean_from_vertical]
///   Push-Up     (left):  [left_elbow_angle (shoulder-elbow-wrist),
///                         body_line_angle (shoulder-hip-ankle)]
///   Pull-Up     (back):  [vertical_shoulder_displacement]
///   Lunge       (left):  [front_knee_angle, torso_lean_angle, shin_angle,
///                         hip_ankle_gap, thigh_angle]
///   Plank       (left):  [back_line_angle, hip_deviation_ratio,
///                         shoulder_elbow_offset]
///   Side Plank  (left):  [back_line_angle, hip_deviation_ratio,
///                         shoulder_elbow_offset]
///
/// NOTE: for Squat/Push-Up/Pull-Up, `AnalysisResult.repSignal` is ALWAYS the
/// vertical displacement (used by camera_screen.dart for rep counting), even
/// though the Squat and Push-Up classifiers' first feature is an angle.
///
/// Squat/Push-Up/Pull-Up need per-session CALIBRATION (a stable one-second
/// window establishes a neutral baseline) for that displacement signal. Only
/// Pull-Up's classifier features also depend on it; Squat and Push-Up
/// classifier features are calibration-free angles, exactly like training.
/// Because of this state, create ONE
/// PoseAnalyzer instance per camera session and call resetCalibration()
/// whenever a new session/exercise starts.
///
/// Training rows for Squat/Push-Up/Pull-Up were taken ONLY at each rep's peak
/// (extract_features.py: find_peaks on feature_1 * -1, i.e. the frame where
/// feature_1 is at its MINIMUM: smallest left knee angle / smallest left
/// elbow angle / most-raised shoulders). So the peak features stored here are those
/// of the frame with the lowest feature_1 in the rep, NOT the frame with the
/// largest hip/shoulder displacement.
/// These exercises are classified ONCE PER REP, on that rep's peak:
///   1. While the rep is descending (before the peak is known) we don't judge
///      form -- the result is "Good form" (neutral, nothing counted against
///      the user).
///   2. The peak is considered reached when the movement starts to reverse
///      (signal drops below the peak by [_peakDropMargin]), when the user
///      dwells at a deep peak for [_dwellDuration], or when the rep ends.
///   3. At that moment the stored peak features are classified exactly once.
///      That verdict is then returned for the remaining engaged frames of the
///      rep, and (if incorrect) held for [_verdictHoldDuration] after the
///      rep ends so the on-screen feedback is actually visible.
///   4. The state is cleared when the next rep starts.
class PoseAnalyzer {
  final Future<KnnVerdict> Function(String exercise, List<double> features)
  _classify;
  final DateTime Function() _clock;

  PoseAnalyzer({
    Future<KnnVerdict> Function(String exercise, List<double> features)?
    classifier,
    DateTime Function()? clock,
  }) : _classify =
           classifier ??
           ((exercise, features) =>
               KnnWorker.instance.classifyDetailed(exercise, features)),
       _clock = clock ?? DateTime.now;

  static const repBasedExercises = {'Squat', 'Push-Up', 'Lunge', 'Pull-Up'};
  static const frontBackExercises = {'Squat', 'Push-Up', 'Pull-Up'};
  static const _correctionMessages = {
    'Squat': 'Check your depth and keep your chest up',
    'Push-Up': 'Check your depth and keep your body in a straight line',
    'Lunge': 'Bend your front knee more and keep your torso upright',
    'Plank': 'Keep your body in a straight line',
    'Pull-Up': 'Pull higher and keep your elbows in',
    'Side Plank': 'Keep your hips lifted and level',
  };

  // ---- Start-position gate ------------------------------------------------
  //
  // Before the user is in the exercise's required starting position, we don't
  // want a misleading green/red verdict. This returns a short on-screen reason
  // (shown with an orange skeleton) when they're clearly not ready yet, or
  // null when they are. Checks are deliberately coarse and scale-free so they
  // work at any distance/height; they only catch gross mis-positioning, not
  // fine form.
  //
  // Geometry (ML Kit normalized coords, y grows downward):
  //   Squat     : needs to be STANDING -- hips clearly above knees, which are
  //               above ankles (vertical stack). If the vertical stack is
  //               collapsed the user is already squatting/sitting or sideways.
  //   Push-Up   : needs to be DOWN in a plank -- shoulder and ankle at nearly
  //               the same height (horizontal body line). Standing up fails it.
  //   Pull-Up   : needs both shoulders visible and hanging low -- checked
  //               separately by the calibration; here we only confirm the body
  //               is roughly upright (shoulders below hips means hanging, which
  //               is the ready state, so we accept it).
  //   Lunge     : needs to be STANDING (both feet on ground, upright torso)
  //               before stepping into a lunge.
  //   Plank     : DOWN in a plank -- shoulder and ankle near the same height.
  //   Side Plank: DOWN on the side -- again a horizontal body line.
  //
  // A "body-line horizontal" test catches standing when you should be prone;
  // a torso-drop test catches being collapsed/sideways when you should be
  // standing. These are the two gross errors the user reported.

  /// Whether the body line (shoulder->ankle) is roughly horizontal, i.e. the
  /// user is prone/planking rather than standing. Used for the ground exercises.
  static bool _bodyLineIsHorizontal(Pose pose) {
    final s = pose.landmarks[_lShoulder];
    final a = pose.landmarks[_lAnkle];
    if (s == null || a == null) return false;
    final dx = (s.x - a.x).abs();
    final dy = (s.y - a.y).abs();
    // Horizontal when the horizontal span is at least as large as the vertical
    // drop -> lying down. Standing gives a tall, narrow span.
    return dx >= dy;
  }

  /// Returns a reason string when the user is not in [exercise]'s starting
  /// position (so the UI can show orange + the message), or null when ready.
  static String? checkStartPosition(String exercise, Pose pose) {
    if (!_reliable(
      pose,
      PoseLandmarkRequirements.forExercise(exercise).toList(),
    )) {
      return null;
    }
    final l = pose.landmarks;
    switch (exercise) {
      case 'Squat':
      case 'Lunge':
        // Must be standing upright: torso vertical (shoulder above hip by a
        // clear margin) and feet on the ground (ankle below hip).
        final s = l[_lShoulder];
        final h = l[_lHip];
        final a = l[_lAnkle];
        if (s == null || h == null || a == null) {
          return null; // landmark check handles it
        }
        final torsoDrop = (h.y - s.y); // positive when hip is below shoulder
        if (torsoDrop < 0.05) {
          return 'Stand up straight to start -- face your left side to the camera';
        }
        if (_bodyLineIsHorizontal(pose)) {
          return 'Stand facing your left side -- we can\'t see your form from this angle';
        }
        return null;
      case 'Push-Up':
      case 'Plank':
      case 'Side Plank':
        // Must be DOWN in a plank: body line horizontal. Standing up fails.
        if (!_bodyLineIsHorizontal(pose)) {
          return exercise == 'Side Plank'
              ? 'Get into a side plank -- lie on your side, body in a straight line'
              : 'Get down into a plank position -- body in a straight line';
        }
        return null;
      case 'Pull-Up':
        // Hanging under the bar: shoulders below hips. If shoulders are ABOVE
        // hips the user is standing on the ground, not hanging. (Distinct local
        // names: Dart switch cases share one scope, so 's'/'h' are taken.)
        final ps = l[_lShoulder];
        final ph = l[_lHip];
        if (ps == null || ph == null) return null;
        if ((ph.y - ps.y) < 0.02) {
          return 'Hang from the bar with your arms straight to start';
        }
        return null;
      default:
        return null;
    }
  }

  static const _lShoulder = PoseLandmarkType.leftShoulder;
  static const _rShoulder = PoseLandmarkType.rightShoulder;
  static const _lElbow = PoseLandmarkType.leftElbow;
  static const _lWrist = PoseLandmarkType.leftWrist;
  static const _rElbow = PoseLandmarkType.rightElbow;
  static const _lHip = PoseLandmarkType.leftHip;
  static const _rHip = PoseLandmarkType.rightHip;
  static const _lKnee = PoseLandmarkType.leftKnee;
  static const _lAnkle = PoseLandmarkType.leftAnkle;

  int _traceCounter = 0;
  final List<double> _calibrationYs = [];
  final List<double> _calibrationScales = [];
  final List<DateTime> _calibrationTimes = [];
  double? _baselineY;
  double? _baselineScale;
  static const Duration _calibrationWindow = Duration(seconds: 1);
  static const Duration _minimumCalibrationWindow = Duration(
    milliseconds: 900,
  );
  static const int _minimumCalibrationSamples = 4;

  /// Stillness threshold for calibration, matching the trainer's
  /// CALIBRATION_STILLNESS_FRACTION (extract_features.py:94). The calibration
  /// window is only accepted when y_range / mean_scale <= this value.
  static const double _calibrationStillnessFraction = 0.06;

  // Must match the engage thresholds in camera_screen.dart.
  static const double _engageThreshold = 0.12;

  // Must match _defaultDownThreshold in camera_screen.dart (a rep only counts
  // once it goes this deep). Used so a pause on the way down at a shallow
  // point isn't mistaken for the bottom of the rep.
  static const double _dwellMinPeak = 0.30;

  // Rep classification uses a plain k=5 majority vote (no hand-tuned
  // incorrect-vote threshold). The earlier per-exercise thresholds were
  // masking thin training data; if you want to revisit them, do it only
  // after re-extracting with more Squat/Push-Up clips, and verify with the
  // "[exercise] rep verdict" debug line (it prints the neighbour vote count).

  // Classifier features of the frame where feature_1 was lowest so far in the
  // rep in progress (this matches how training rows were picked).
  List<double>? _peakFeatures;
  // Largest (signed-adjusted) displacement so far in this rep. Used ONLY for
  // timing (reversal / dwell detection), never for choosing features.
  double _peakSignal = 0;
  bool _hasPeakSignal = false;

  // Exponential moving average of [displacement, ...classifierFeatures], so a
  // single jittery frame can't become the rep's "peak".
  List<double>? _emaRaw;
  static const double _emaAlpha = 0.5;

  // Wall-clock timing keeps rep decisions consistent when the camera adapts
  // its frame-skip interval to device performance.
  DateTime? _engagedSince;
  static const Duration _minimumEngagement = Duration(milliseconds: 200);

  // ---- Per-rep verdict state ----
  // True once the current rep's peak has been classified (exactly once).
  bool _repCommitted = false;
  // The committed verdict for the current rep (null until committed).
  bool? _repVerdict;
  // Kept separate from a missing verdict so OOD is not reported as an
  // unavailable model.
  bool _repOutOfDistribution = false;
  // Time since the peak signal last increased (used to detect a pause at the
  // bottom before the user starts coming back up).
  DateTime? _peakLastImprovedAt;
  DateTime? _verdictHoldUntil;

  // The movement has reversed once the signal falls this far below the peak
  // (displacement is normalised by torso/shoulder length).
  static const double _peakDropMargin = 0.04;
  // Ignore tiny EMA/noise increases so a stable hold can satisfy dwell timing.
  static const double _peakImprovementThreshold = 0.01;
  // Time-based thresholds remain stable as camera frame skipping adapts.
  static const Duration _dwellDuration = Duration(milliseconds: 400);
  static const Duration _verdictHoldDuration = Duration(seconds: 1);

  // Smooths per-frame verdicts for Lunge/Plank/Side Plank so scoring and display
  // don't react to single misclassified frames.
  final FormSmoother _smoother = FormSmoother(windowSize: 5, minFrames: 3);

  // ---- Landmark smoothing (display only) ----
  // ML Kit jitters each joint by a few pixels frame-to-frame. A light EMA on the
  // DRAWN coordinates makes the skeleton glide instead of shaking, without
  // touching the raw pose used for classification (features stay faithful).
  final Map<PoseLandmarkType, _Point3D> _lmEma = {};
  // Landmark EMA. 0.7 keeps a little jitter rejection while adding far less
  // lag than 0.5; the smoothing ablation showed EMA buys ~0 accuracy on the
  // frame-classified exercises, so favouring responsiveness here is free.
  static const double _lmEmaAlpha = 0.7;

  /// Returns a copy of [pose] whose x/y are a light EMA of recent frames.
  /// The returned pose carries the same likelihoods and types, so reliability
  /// checks behave identically. Resets cleanly via [resetCalibration].
  Pose _smoothPose(Pose pose) {
    final smoothed = <PoseLandmarkType, PoseLandmark>{};
    for (final lm in pose.landmarks.values) {
      final prev = _lmEma[lm.type];
      if (prev == null) {
        _lmEma[lm.type] = _Point3D(lm.x, lm.y);
        smoothed[lm.type] = lm;
        continue;
      }
      final x = _lmEmaAlpha * lm.x + (1 - _lmEmaAlpha) * prev.x;
      final y = _lmEmaAlpha * lm.y + (1 - _lmEmaAlpha) * prev.y;
      _lmEma[lm.type] = _Point3D(x, y);
      smoothed[lm.type] = PoseLandmark(
        type: lm.type,
        x: x,
        y: y,
        z: lm.z,
        likelihood: lm.likelihood,
      );
    }
    return Pose(landmarks: smoothed);
  }

  void resetCalibration() {
    _calibrationYs.clear();
    _calibrationScales.clear();
    _calibrationTimes.clear();
    _lmEma.clear();
    _baselineY = null;
    _baselineScale = null;
    _clearRepState();
    _emaRaw = null;
    _smoother.reset();
  }

  void _clearRepState() {
    _peakFeatures = null;
    _hasPeakSignal = false;
    _peakSignal = 0;
    _engagedSince = null;
    _peakLastImprovedAt = null;
    _repCommitted = false;
    _repVerdict = null;
    _repOutOfDistribution = false;
    _verdictHoldUntil = null;
  }

  static double _angle(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
    final radians = atan2(c.y - b.y, c.x - b.x) - atan2(a.y - b.y, a.x - b.x);
    var angle = (radians * 180 / pi).abs();
    if (angle > 180) angle = 360 - angle;
    return angle;
  }

  static double _dist(PoseLandmark a, PoseLandmark b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return sqrt(dx * dx + dy * dy);
  }

  static _Point2D _midpoint(PoseLandmark a, PoseLandmark b) {
    return _Point2D((a.x + b.x) / 2, (a.y + b.y) / 2);
  }

  static bool _reliable(Pose pose, List<PoseLandmarkType> types) {
    for (final t in types) {
      final lm = pose.landmarks[t];
      if (lm == null || lm.likelihood < 0.6) return false;
    }
    return true;
  }

  static double _torsoLength(Pose pose) {
    final shoulderMid = _midpoint(
      pose.landmarks[_lShoulder]!,
      pose.landmarks[_rShoulder]!,
    );
    final hipMid = _midpoint(pose.landmarks[_lHip]!, pose.landmarks[_rHip]!);
    final dx = shoulderMid.x - hipMid.x;
    final dy = shoulderMid.y - hipMid.y;
    return sqrt(dx * dx + dy * dy);
  }

  /// Push-Up uses the left shoulder-to-hip length for its left-profile view.
  static double _calibrationScale(String exercise, Pose pose) {
    if (exercise == 'Push-Up') {
      return _dist(pose.landmarks[_lShoulder]!, pose.landmarks[_lHip]!);
    }
    return _torsoLength(pose);
  }

  static _Point2D _referencePoint(String exercise, Pose pose) {
    if (exercise == 'Squat') {
      return _midpoint(pose.landmarks[_lHip]!, pose.landmarks[_rHip]!);
    } else if (exercise == 'Push-Up') {
      final shoulder = pose.landmarks[_lShoulder]!;
      return _Point2D(shoulder.x, shoulder.y);
    } else {
      return _midpoint(
        pose.landmarks[_lShoulder]!,
        pose.landmarks[_rShoulder]!,
      );
    }
  }

  // ---- Left-side angle features: must stay identical to extract_features.py ----

  /// squat_knee_angle(): left hip-knee-ankle. ~170+ standing, smaller = deeper.
  static double _squatKneeAngle(Pose pose) => _angle(
    pose.landmarks[_lHip]!,
    pose.landmarks[_lKnee]!,
    pose.landmarks[_lAnkle]!,
  );

  /// squat_torso_lean() / Lunge torso lean: left shoulder-hip line from
  /// vertical in degrees (0 = upright).
  static double _torsoLeanAngle(Pose pose) {
    final shoulder = pose.landmarks[_lShoulder]!;
    final hip = pose.landmarks[_lHip]!;
    final dx = shoulder.x - hip.x;
    final dy = shoulder.y - hip.y;
    return (atan2(dx, -dy) * 180 / pi).abs();
  }

  /// pushup_elbow_angle(): left shoulder-elbow-wrist. ~170+ at the top,
  /// shrinking toward ~70-90 at the bottom.
  static double _pushupElbowAngle(Pose pose) => _angle(
    pose.landmarks[_lShoulder]!,
    pose.landmarks[_lElbow]!,
    pose.landmarks[_lWrist]!,
  );

  /// pushup_body_line_angle(): left shoulder-hip-ankle. ~180 = straight line.
  static double _pushupBodyLineAngle(Pose pose) => _angle(
    pose.landmarks[_lShoulder]!,
    pose.landmarks[_lHip]!,
    pose.landmarks[_lAnkle]!,
  );

  /// feature_2 (feature_2_value() in extract_features.py).
  static double _bonusRatio(String exercise, Pose pose) {
    if (exercise == 'Squat') return _torsoLeanAngle(pose);
    if (exercise == 'Push-Up') return _pushupBodyLineAngle(pose);
    final elbowDist = _dist(pose.landmarks[_lElbow]!, pose.landmarks[_rElbow]!);
    final shoulderDist = _dist(
      pose.landmarks[_lShoulder]!,
      pose.landmarks[_rShoulder]!,
    );
    return shoulderDist > 1e-6 ? elbowDist / shoulderDist : 0;
  }

  bool _tryCalibrate(String exercise, Pose pose) {
    if (_baselineY != null) return true;
    final ref = _referencePoint(exercise, pose);
    final scale = _calibrationScale(exercise, pose);
    if (scale < 1e-6) return false;
    final now = _clock();
    _calibrationYs.add(ref.y);
    _calibrationScales.add(scale);
    _calibrationTimes.add(now);
    // Keep a time-based sliding window so slower devices use the same
    // calibration duration and stillness interval as faster devices.
    while (_calibrationTimes.length > 1 &&
        now.difference(_calibrationTimes.first) > _calibrationWindow) {
      _calibrationTimes.removeAt(0);
      _calibrationYs.removeAt(0);
      _calibrationScales.removeAt(0);
    }
    if (_calibrationYs.length >= _minimumCalibrationSamples &&
        now.difference(_calibrationTimes.first) >= _minimumCalibrationWindow) {
      // Stillness check: the window must be stable before locking the baseline.
      // The trainer uses CALIBRATION_STILLNESS_FRACTION = 0.06 (y_range / mean_scale).
      // Without this, a user who is still moving gets a poor baseline, which
      // directly affects Pull-Up's displacement feature and rep timing.
      final meanScale =
          _calibrationScales.reduce((a, b) => a + b) /
          _calibrationScales.length;
      final yRange =
          _calibrationYs.reduce((a, b) => a > b ? a : b) -
          _calibrationYs.reduce((a, b) => a < b ? a : b);
      if (meanScale > 1e-6 &&
          yRange / meanScale <= _calibrationStillnessFraction) {
        _baselineY =
            _calibrationYs.reduce((a, b) => a + b) / _calibrationYs.length;
        _baselineScale = meanScale;
      }
    }
    return _baselineY != null;
  }

  /// Squat only: keeps the standing baseline in step with where the hips
  /// really are while the user is standing. The one-off calibration at the
  /// start of a session goes stale as soon as the user steps, shifts or
  /// finishes walking into frame; the displacement then sits far from 0 (the
  /// trace showed -0.7) and a squat can never reach the engage threshold, so
  /// no rep is ever judged and the skeleton stays green.
  ///
  /// Only updates when the user is upright (knee straight), not mid-rep, and
  /// not descending, so a real squat never drags the baseline down with it.
  void _trackSquatBaseline(Pose pose, _Point2D ref) {
    if (_engagedSince != null) return;
    if (_squatKneeAngle(pose) < 150) return;
    final d = (ref.y - _baselineY!) / _baselineScale!;
    final double alpha;
    if (d < -0.05) {
      alpha = 0.3; // clearly above the baseline: re-anchor quickly
    } else if (d <= 0.05) {
      alpha = 0.05; // standing still: follow slow drift
    } else {
      return; // possibly the start of a descent: leave the baseline alone
    }
    _baselineY = _baselineY! + alpha * (ref.y - _baselineY!);
    final scale = _torsoLength(pose);
    if (scale > 1e-6) {
      _baselineScale = _baselineScale! + alpha * (scale - _baselineScale!);
    }
  }

  List<double> _classifierFeatures(
    String exercise,
    Pose pose,
    double displacement,
  ) {
    if (exercise == 'Squat') {
      return [_squatKneeAngle(pose), _bonusRatio(exercise, pose)];
    }
    if (exercise == 'Push-Up') {
      return [_pushupElbowAngle(pose), _bonusRatio(exercise, pose)];
    }
    // Pull-Up is 1-D on purpose. The old second feature (elbow/shoulder spread
    // ratio) measured 0.35 sigma separation and AUC 0.587 -- barely above
    // chance -- and a grouped-CV leave-one-out showed REMOVING it raised
    // accuracy from 70.3% to 73.5%. None of the frame-local replacement
    // candidates beat that: pl_elbow_asym scored 80.3% but with AUC 0.211,
    // i.e. it predicted the label backwards and was fitting the clip set
    // rather than form quality, so it was rejected. Pull-Up therefore ships
    // with the vertical-displacement feature only.
    return [displacement];
  }

  List<double> _lungeFeatures(Pose pose) {
    final hip = pose.landmarks[_lHip]!;
    final knee = pose.landmarks[_lKnee]!;
    final ankle = pose.landmarks[_lAnkle]!;
    final shoulder = pose.landmarks[_lShoulder]!;
    final kneeAngle = _angle(hip, knee, ankle);
    final dx = shoulder.x - hip.x;
    final dy = shoulder.y - hip.y;
    final torsoLean = atan2(dx, -dy).abs() * 180 / pi;
    // Front shin angle from vertical (knee-over-ankle).
    final shinAngle =
        atan2(knee.x - ankle.x, ankle.y - knee.y).abs() * 180 / pi;
    // Normalized hip-to-ankle vertical gap over trunk length (lunge depth).
    // Matches the Python extractor's _div(): NaN when the denominator is
    // ~0, so a degenerate frame is rejected by the classifier's finite
    // check rather than scored as a 0-length torso.
    final trunk = _dist(shoulder, hip);
    final hipAnkleGap = trunk.abs() > 1e-6
        ? (ankle.y - hip.y) / trunk
        : double.nan;
    // Front thigh angle from vertical (depth / stance).
    final thighAngle = atan2(knee.x - hip.x, knee.y - hip.y).abs() * 180 / pi;
    return [kneeAngle, torsoLean, shinAngle, hipAnkleGap, thighAngle];
  }

  List<double> _plankStyleFeatures(Pose pose) {
    final shoulder = pose.landmarks[_lShoulder]!;
    final hip = pose.landmarks[_lHip]!;
    final ankle = pose.landmarks[_lAnkle]!;
    final elbow = pose.landmarks[_lElbow]!;
    final backAngle = _angle(shoulder, hip, ankle);
    final lineLen = _dist(shoulder, ankle);
    double hipDeviation = 0;
    if (lineLen > 1e-6) {
      final numerator =
          ((ankle.y - shoulder.y) * hip.x -
                  (ankle.x - shoulder.x) * hip.y +
                  ankle.x * shoulder.y -
                  ankle.y * shoulder.x)
              .abs();
      hipDeviation = numerator / lineLen / lineLen;
    }
    // Third feature: horizontal shoulder-to-elbow offset, normalised by the
    // shoulder-ankle line length. MUST stay identical to pk_shoulder_elbow_dx
    // in extract_features.py (Python side), or train/serve skew silently
    // kills accuracy. Raises Plank/Side Plank grouped-CV accuracy ~0.72 -> 0.82.
    final double shoulderElbowDx = lineLen > 1e-6
        ? (shoulder.x - elbow.x).abs() / lineLen
        : 0.0;
    return [backAngle, hipDeviation, shoulderElbowDx];
  }

  /// Classifies the stored peak once. OOD is committed as a distinct state;
  /// unavailable model results remain uncommitted.
  Future<KnnVerdict> _commitRepVerdict(String exercise, String reason) async {
    final features = _peakFeatures;
    if (features == null) return const KnnVerdict.unavailable();
    final detailed = await _classify(exercise, features);
    if (detailed.isOutOfDistribution) {
      _repCommitted = true;
      _repVerdict = null;
      _repOutOfDistribution = true;
      _verdictHoldUntil = _clock().add(_verdictHoldDuration);
      return detailed;
    }
    final verdict = detailed.isCorrect;
    if (verdict == null) return detailed; // model unavailable
    _repCommitted = true;
    _repVerdict = verdict;
    _repOutOfDistribution = false;
    _verdictHoldUntil = verdict
        ? null
        : _clock().add(_verdictHoldDuration);
    if (kDebugMode) {
      debugPrint(
        '[$exercise] rep verdict ($reason): peak=$features '
        'signal=${_peakSignal.toStringAsFixed(2)} '
        'verdict=$verdict',
      );
    }
    return detailed;
  }

  /// Judge a rep that is still in progress when the session ends, so a squat
  /// the user stopped mid-way (or tapped Stop at the bottom) is still scored
  /// instead of silently dropped. Call from CameraScreen._endSession() before
  /// saving the session. No-op when there's nothing to judge.
  Future<void> finalizeRep(String exercise) async {
    if (_peakFeatures != null &&
        !_repCommitted &&
        _hasMinimumEngagement()) {
      await _commitRepVerdict(exercise, 'session ended');
    }
  }

  bool _hasMinimumEngagement() {
    final started = _engagedSince;
    return started != null &&
        _clock().difference(started) >= _minimumEngagement;
  }

  AnalysisResult _repVerdictResult(
    String exercise,
    double repSignal, [
    Pose? smoothedPose,
  ]) {
    if (_repOutOfDistribution) {
      return AnalysisResult(
        false,
        'Unfamiliar form - try to match the guide',
        repSignal,
        landmarksReliable: false,
        smoothedPose: smoothedPose,
      );
    }
    final verdict = _repVerdict ?? true;
    final message = verdict
        ? 'Good form'
        : (_correctionMessages[exercise] ?? 'Adjust your form');
    return AnalysisResult(
      verdict,
      message,
      repSignal,
      smoothedPose: smoothedPose,
    );
  }

  Future<AnalysisResult> analyze(String exercise, Pose pose) async {
    final notReady = checkStartPosition(exercise, pose);
    if (notReady != null) {
      return AnalysisResult(
        false,
        notReady,
        0,
        landmarksReliable: false,
        smoothedPose: pose,
      );
    }

    if (frontBackExercises.contains(exercise)) {
      final required = PoseLandmarkRequirements.forExercise(exercise).toList();
      if (!_reliable(pose, required)) {
        _emaRaw = null;
        return AnalysisResult(
          false,
          'Can\'t see you clearly - step back so your whole body is in frame',
          0,
          landmarksReliable: false,
        );
      }
      if (!_tryCalibrate(exercise, pose)) {
        return AnalysisResult(
          true,
          'Calibrating - hold your starting position',
          0,
          landmarksReliable: false,
        );
      }
      // Smoothed pose for drawing only. Computed once, after reliability passes,
      // before any classification branch returns.
      final smoothedPose = _smoothPose(pose);

      final ref = _referencePoint(exercise, pose);
      if (exercise == 'Squat') _trackSquatBaseline(pose, ref);
      final displacement = (ref.y - _baselineY!) / _baselineScale!;
      final cls = _classifierFeatures(exercise, pose, displacement);
      final raw = [displacement, ...cls];

      final prev = _emaRaw;
      final smoothed = prev == null
          ? raw
          : [
              for (var i = 0; i < raw.length; i++)
                _emaAlpha * raw[i] + (1 - _emaAlpha) * prev[i],
            ];
      _emaRaw = smoothed;

      final motion = smoothed[0];
      final clsFeatures = smoothed.sublist(1);

      // Must stay the raw displacement: camera_screen.dart counts reps with it.
      final repSignal = displacement;

      final sign = exercise == 'Pull-Up' ? -1.0 : 1.0;
      final signal = motion * sign;

      if (kDebugMode && ++_traceCounter % 3 == 0) {
        debugPrint(
          '[$exercise trace] disp=${motion.toStringAsFixed(2)} '
          'engage>=${_engageThreshold.toStringAsFixed(2)} '
          'features=$clsFeatures '
          'engaged=${_engagedSince != null} committed=$_repCommitted '
          'baselineY=${_baselineY!.toStringAsFixed(0)} '
          'scale=${_baselineScale!.toStringAsFixed(0)}',
        );
      }

      // ---- Not engaged: idle, or the rep has just finished ----
      if (signal < _engageThreshold) {
        // A rep that ended before we saw a reversal / dwell (very quick rep):
        // classify its peak now so it still gets a verdict.
        if (_peakFeatures != null &&
            !_repCommitted &&
            _hasMinimumEngagement()) {
          await _commitRepVerdict(exercise, 'rep ended');
        }

        _peakFeatures = null;
        _hasPeakSignal = false;
        _peakSignal = 0;
        _engagedSince = null;
        _peakLastImprovedAt = null;

        // Keep showing an incorrect verdict briefly after standing back up,
        // otherwise the ascent is often only 1-3 frames and the feedback
        // would flash by unseen.
        if (_repCommitted &&
            (_repVerdict == false || _repOutOfDistribution) &&
            _verdictHoldUntil != null &&
            _clock().isBefore(_verdictHoldUntil!)) {
          return _repVerdictResult(exercise, repSignal, smoothedPose);
        }
        _repCommitted = false;
        _repVerdict = null;
        _repOutOfDistribution = false;
        _verdictHoldUntil = null;
        // Not in a rep (standing / between reps / a rep that hasn't been judged
        // yet): this is NEUTRAL, not "Good form". Claiming green here with no
        // classifier verdict is what made unjudged frames show a false green.
        return AnalysisResult(
          false,
          'Stand ready -- start your rep',
          repSignal,
          landmarksReliable: false,
          smoothedPose: smoothedPose,
        );
      }

      // ---- Engaged ----
      if (_engagedSince == null) {
        // First engaged frame of a new rep: drop the previous rep's verdict.
        _engagedSince = _clock();
        _repCommitted = false;
        _repVerdict = null;
        _repOutOfDistribution = false;
        _verdictHoldUntil = null;
      }

      if (!_repCommitted) {
        // Peak FEATURES: the frame where feature_1 is lowest so far, exactly
        // like the training extraction (smallest left knee angle for Squat,
        // smallest left elbow angle for Push-Up, most-raised shoulders for
        // Pull-Up).
        if (_peakFeatures == null || clsFeatures[0] < _peakFeatures![0]) {
          _peakFeatures = clsFeatures;
        }
        // Peak TIMING: based on displacement, used only to decide when the
        // bottom of the rep has been reached.
        if (!_hasPeakSignal ||
            signal > _peakSignal + _peakImprovementThreshold) {
          _hasPeakSignal = true;
          _peakSignal = signal;
          _peakLastImprovedAt = _clock();
        }

        if (_hasMinimumEngagement()) {
          final reversed = signal <= _peakSignal - _peakDropMargin;
          final dwelling =
              _peakSignal >= _dwellMinPeak &&
              _peakLastImprovedAt != null &&
              _clock().difference(_peakLastImprovedAt!) >= _dwellDuration;
          if (reversed || dwelling) {
            final verdict = await _commitRepVerdict(
              exercise,
              reversed ? 'reversal' : 'dwell',
            );
            if (!verdict.isOutOfDistribution && verdict.isCorrect == null) {
              return AnalysisResult(
                false,
                'Form model unavailable',
                repSignal,
                landmarksReliable: false,
              );
            }
          }
        }
      }

      // Before the peak is known we don't judge the rep. Show a NEUTRAL
      // "hold" state, NOT green -- an unjudged rep must never read as good
      // form (that hid every wrong squat whose pose was out-of-distribution
      // for the tiny Squat model). landmarksReliable=false renders it orange.
      if (!_repCommitted) {
        return AnalysisResult(
          true,
          'Hold at the bottom of the rep',
          repSignal,
          smoothedPose: smoothedPose,
          landmarksReliable: false,
        );
      }
      return _repVerdictResult(exercise, repSignal, smoothedPose);
    } else {
      final required = PoseLandmarkRequirements.forExercise(exercise).toList();
      if (!_reliable(pose, required)) {
        _smoother.reset();
        return AnalysisResult(
          false,
          'Can\'t see you clearly - step back so your whole body is in frame',
          0,
          landmarksReliable: false,
        );
      }
      final smoothedPose = _smoothPose(pose);
      final features = exercise == 'Lunge'
          ? _lungeFeatures(pose)
          : _plankStyleFeatures(pose);
      final verdict = await _classify(exercise, features);
      if (kDebugMode && ++_traceCounter % 3 == 0) {
        debugPrint(
          '[$exercise frame] features='
          '[${features.map((f) => f.toStringAsFixed(1)).join(", ")}] '
          'verdict=${verdict.isCorrect} ood=${verdict.isOutOfDistribution}',
        );
      }
      // Out-of-distribution: this pose is unlike anything the model was
      // trained on. Show an honest "can't judge" state rather than guessing
      // Correct or Incorrect (which is what caused wrong forms performed in
      // an untrained way to show a false green).
      if (verdict.isOutOfDistribution) {
        _smoother.reset();
        return AnalysisResult(
          false,
          'Unfamiliar form - try to match the guide',
          features[0],
          landmarksReliable: false,
        );
      }
      final raw = verdict.isCorrect;
      if (raw == null) {
        _smoother.reset();
        return AnalysisResult(
          false,
          'Form model unavailable',
          features[0],
          landmarksReliable: false,
        );
      }
      final isCorrect = _smoother.add(raw);
      final message = isCorrect
          ? 'Good form'
          : (_correctionMessages[exercise] ?? 'Adjust your form');
      return AnalysisResult(
        isCorrect,
        message,
        features[0],
        smoothedPose: smoothedPose,
      );
    }
  }
}
