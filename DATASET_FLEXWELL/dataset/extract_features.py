"""
extract_features.py

CAMERA PLACEMENT UPDATE: Squat and Push-Up are now filmed from the user's LEFT
SIDE (like Lunge/Plank/Side Plank). They are still rep-based (one row per rep
at the rep peak = minimum of feature_1), and calibration-free:
  Squat:   feature_1 = left knee angle,  feature_2 = torso lean from vertical
  Push-Up: feature_1 = left elbow angle, feature_2 = shoulder-hip-ankle angle
Old front-view data for these two exercises is NOT comparable -- re-record.
Pull-Up is unchanged (back view). The "front/back" names below are kept only
because they select the rep-based code path.
Walks a folder of labeled videos and extracts a per-exercise feature vector
for training the FlexWell KNN classifier.
Each exercise now uses exactly the 2 features actually measurable from ITS
assigned camera placement (see the table above). Squat/Push-Up/Pull-Up use
a per-video CALIBRATION step (the first ~10 detected frames establish a
neutral baseline) since their depth signal is vertical displacement
relative to a starting position, not a fixed angle.

Fixes applied after diagnostics on the first dataset pull:

1. Push-Up normalization. Push-Up is filmed front-on with the torso
   extending in depth away from the camera, so the old scale reference
   (shoulder-midpoint-to-hip-midpoint distance) foreshortens toward zero
   for nearly every clip, blowing up vertical_displacement into noise
   (values as large as 16x torso length were observed). Push-Up now
   normalizes against shoulder width instead, which runs roughly
   left-right (perpendicular to the camera axis) and stays stable
   regardless of how compressed the body looks in depth. Squat and
   Pull-Up keep the original torso-length scale, which tested fine.

2. Rep-level features instead of per-frame rows. AUC testing showed the
   real signal for Squat/Pull-Up lives at the PEAK of each rep (deepest
   squat, highest pull), not in the raw per-frame value or the whole-clip
   average -- a frame near the top of a rep looks the same whether the
   rep itself was executed well or not. Squat/Push-Up/Pull-Up now detect
   individual reps per video (via peaks in vertical_displacement) and
   emit exactly one row per rep, taken at that rep's peak frame, instead
   of one row per sampled frame. This also fixes the earlier problem of
   rows-per-video varying wildly (6 to 212) -- rep counts are naturally
   far more consistent across videos of the same exercise.

3. Push-Up feature_2: elbow bend angle, not elbow-flare ratio. AUC testing
   showed elbow_distance/shoulder_distance sits at AUC<=0.60 for Push-Up --
   that ratio mostly tracks how wide the elbows flare outward, not how far
   the body has descended. feature_2 for Push-Up is now the elbow bend
   angle (shoulder-elbow-wrist, averaged left/right), which directly
   measures arm extension/depth the same way front_knee_angle does for
   Lunge. Squat's knee/hip-width ratio and Pull-Up's elbow/shoulder ratio
   are unchanged -- both already tested with usable signal.

4. Rep-detection fallback for short/noisy clips. Several Pull-Up videos
   were yielding 0 detected reps even though vertical_displacement clearly
   varied -- MIN_REP_PROMINENCE_FRACTION/MIN_REP_SPACING_SECONDS, tuned for
   a "typical" clip length, were too strict for some clips (very short
   clips in particular can't fit a peak at the default minimum spacing).
   If the default thresholds find nothing, extraction now retries once
   with half the prominence requirement and half the spacing requirement
   before giving up on that video, and logs when the fallback was what
   found the reps -- so you can see which videos needed it and decide
   whether the defaults should just be relaxed globally, or whether those
   specific clips are too short/noisy to use at all.

Output: features.csv with columns:
  exercise, label, feature_1, feature_2, video_id
"""
import os
import math
import cv2
import mediapipe as mp
import numpy as np
import pandas as pd
from scipy.signal import find_peaks
mp_pose = mp.solutions.pose
# The exercise folders live beside this script. Resolve them from __file__ so
# the script works whether it is launched from the project root or this folder.
DATASET_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_CSV = "features.csv"
L_SHOULDER, R_SHOULDER = 11, 12
L_ELBOW, R_ELBOW = 13, 14
L_WRIST, R_WRIST = 15, 16
L_HIP, R_HIP = 23, 24
L_EAR = 7
L_HEEL, L_FOOT_INDEX = 29, 31
L_KNEE, R_KNEE = 25, 26
L_ANKLE, R_ANKLE = 27, 28
CALIBRATION_FRAMES = 10
# Calibration only locks in once the last CALIBRATION_FRAMES are STILL: the
# reference point's y-range must stay within this fraction of the scale.
# Without this, calibration can complete while the subject is still walking
# into frame or already mid-rep, corrupting baseline_y/baseline_scale for the
# rest of that video -- every later displacement value inherits the error.
# Matches the runtime gate added to pose_analyzer.dart.
CALIBRATION_STILLNESS_FRACTION = 0.06
# Rows more than this many standard deviations from their exercise's mean (on
# either feature) are treated as bad-clip outliers and dropped, so they don't
# inflate the std used for z-score normalization on the phone.
OUTLIER_STD = 4.0
# Baseline-scale gate. displacement = (y - baseline_y) / baseline_scale, so a
# clip whose calibration scale is far smaller than its exercise's norm (partial
# framing, lean, landmark glitch in the first frames) blows up into huge
# values. After all videos are processed, any Squat/Push-Up/Pull-Up clip whose
# baseline_scale is below this fraction of its exercise's MEDIAN is dropped.
MIN_BASELINE_SCALE_FRACTION = 0.5
VIDEO_BASELINE_SCALES = {}  # video_id -> baseline_scale, filled during extraction
VIDEO_REST_VALUES = {}  # video_id -> feature_1 value before the first rep starts (diagnostic only,
                          # not used for training; helps set real UI phase-detection thresholds later)
# Per-clip detection stats (diagnostic only, not used for training). Explains why
# row counts differ across clips of the same exercise: a clip whose body leaves
# the frame or whose landmarks drop below the visibility threshold loses rows,
# which is the real cause of correct/incorrect ROW imbalance even when the
# VIDEO counts are balanced. Written to detection_stats.csv in main().
VIDEO_DETECTION_STATS = {}  # video_id -> dict(total_frames, detected_frames, rows, detection_pct)
SIDE_VIEW_EXERCISES = {"Lunge", "Plank", "Side Plank"}
FRONT_BACK_EXERCISES = {"Squat", "Push-Up", "Pull-Up"}  # = rep-based path (Squat/Push-Up are now left-side)
# +1 exercises: a rep's peak is the MAXIMUM of vertical_displacement (moving
# down/away from the camera reads as a larger y => larger displacement).
# -1 exercises: a rep's peak is the MINIMUM (pulling up reads as smaller y
# => more negative displacement). See raw_reference_point()/bonus logic
# below for how each exercise's reference point is chosen.
# Squat/Pull-Up: peak is the MAXIMUM/MINIMUM of calibrated vertical
# displacement (see comment above). Push-Up now uses pushup_elbow_angle() (left side),
# which shrinks at the bottom of the rep, so its peak is the MINIMUM.
# Squat now uses squat_knee_angle(), which shrinks toward the bottom of the
# rep (like Push-Up's depth ratio), so its peak is the MINIMUM too. Pull-Up
# still uses calibrated displacement and keeps its existing sign.
REP_PEAK_SIGN = {"Squat": -1, "Push-Up": -1, "Pull-Up": -1}
MIN_REP_PROMINENCE_FRACTION = 0.15  # peak must stand out by >=15% of the clip's own displacement range
MIN_REP_SPACING_SECONDS = 0.5       # reps can't be detected closer together than this (guards against jitter)
def open_video(path):
    """Open a video and make sure phone-recorded rotation is applied.

    Portrait phone clips are often stored sideways with a rotation flag.
    If OpenCV ignores it, the person appears rotated, which corrupts any
    orientation-dependent feature (e.g. Lunge torso lean, all y-displacement).
    Returns (cap, rotate_code); rotate_code is None when OpenCV handles it.
    """
    cap = cv2.VideoCapture(path)
    meta = int(cap.get(cv2.CAP_PROP_ORIENTATION_META) or 0)
    auto_ok = bool(cap.set(cv2.CAP_PROP_ORIENTATION_AUTO, 1))
    rotate_code = None
    if meta in (90, 180, 270):
        if not auto_ok:
            rotate_code = {90: cv2.ROTATE_90_CLOCKWISE,
                           180: cv2.ROTATE_180,
                           270: cv2.ROTATE_90_COUNTERCLOCKWISE}[meta]
        print(f"  {path}: rotation metadata {meta} deg "
              f"({'auto-applied by OpenCV' if auto_ok else 'applying manually'})")
    return cap, rotate_code
def read_frame(cap, rotate_code):
    success, frame = cap.read()
    if success and rotate_code is not None:
        frame = cv2.rotate(frame, rotate_code)
    return success, frame
def calculate_angle(a, b, c):
    radians = math.atan2(c.y - b.y, c.x - b.x) - math.atan2(a.y - b.y, a.x - b.x)
    angle = abs(math.degrees(radians))
    if angle > 180:
        angle = 360 - angle
    return angle
def euclidean(a, b):
    return math.hypot(a.x - b.x, a.y - b.y)
def midpoint(a, b):
    class _Point:
        pass
    p = _Point()
    p.x = (a.x + b.x) / 2
    p.y = (a.y + b.y) / 2
    return p
def to_pixel_landmarks(landmarks, width, height):
    """MediaPipe returns x/y normalized separately by frame width and height,
    so on a non-square frame distances and angles are anisotropically
    distorted. ML Kit on the phone returns isotropic pixel coordinates, so
    scale to pixels here to make training features match on-device features.
    """
    class _Pt:
        __slots__ = ("x", "y")
        def __init__(self, x, y):
            self.x = x
            self.y = y
    return [_Pt(l.x * width, l.y * height) for l in landmarks]
def features_lunge(lm):
    """Lunge feature vector, LEFT-SIDE camera. 5 features.

    Validated in lunge_validate.py with leakage-free grouped CV:
      2 features (knee + torso lean) -> 0.711 mean / 0.726 holdout
      5 features (below)            -> 0.823 mean / 0.863 holdout
    The 3 added features are the shin angle, the hip-to-ankle gap, and the
    front thigh angle; they capture knee-over-toe position and lunge depth,
    which the original two features could not separate. The 4/5-feature set
    beat the 2-feature set on 10/10 random video-grouped splits.

    MUST stay numerically identical to _lungeFeatures in pose_analyzer.dart.
    """
    hip, knee, ankle = lm[L_HIP], lm[L_KNEE], lm[L_ANKLE]
    shoulder = lm[L_SHOULDER]
    front_knee_angle = calculate_angle(hip, knee, ankle)
    dx = shoulder.x - hip.x
    dy = shoulder.y - hip.y
    torso_lean_angle = abs(math.degrees(math.atan2(dx, -dy)))
    # front shin angle from vertical (knee-over-ankle): ~0 = shin vertical,
    # larger = knee drifting forward of the foot.
    shin_angle = abs(math.degrees(math.atan2(knee.x - ankle.x, ankle.y - knee.y)))
    # normalized hip-to-ankle vertical gap over trunk length (lunge depth).
    trunk = euclidean(shoulder, hip)
    hip_ankle_gap = _div(ankle.y - hip.y, trunk)
    # front thigh angle from vertical (depth / stance).
    thigh_angle = abs(math.degrees(math.atan2(knee.x - hip.x, knee.y - hip.y)))
    return [front_knee_angle, torso_lean_angle, shin_angle, hip_ankle_gap, thigh_angle]
def features_plank_style(lm):
    shoulder, hip, ankle = lm[L_SHOULDER], lm[L_HIP], lm[L_ANKLE]
    elbow = lm[L_ELBOW]
    back_line_angle = calculate_angle(shoulder, hip, ankle)
    line_len = euclidean(shoulder, ankle)
    if line_len < 1e-6:
        hip_deviation_ratio = 0.0
    else:
        numerator = abs(
            (ankle.y - shoulder.y) * hip.x
            - (ankle.x - shoulder.x) * hip.y
            + ankle.x * shoulder.y
            - ankle.y * shoulder.x
        )
        hip_deviation_ratio = numerator / line_len / line_len
    # Third feature: horizontal shoulder-to-elbow offset, normalised by the
    # shoulder-ankle line length. MUST stay identical to the Dart side
    # (_plankStyleFeatures in pose_analyzer.dart). Raises Plank/Side Plank
    # grouped-CV accuracy ~0.72 -> 0.82.
    shoulder_elbow_dx = abs(shoulder.x - elbow.x) / line_len if line_len >= 1e-6 else 0.0
    return [back_line_angle, hip_deviation_ratio, shoulder_elbow_dx]
def torso_length(lm):
    shoulder_mid = midpoint(lm[L_SHOULDER], lm[R_SHOULDER])
    hip_mid = midpoint(lm[L_HIP], lm[R_HIP])
    return euclidean(shoulder_mid, hip_mid)
def pushup_elbow_angle(lm):
    """Push-Up depth signal, LEFT-SIDE camera: left shoulder-elbow-wrist angle.
    ~170+ deg at the top, shrinking toward ~70-90 deg at the bottom. From the
    side the elbow angle is a true 2D angle (no foreshortening), and it needs
    no calibration. Peak of a rep = the MINIMUM (REP_PEAK_SIGN = -1).
    """
    return calculate_angle(lm[L_SHOULDER], lm[L_ELBOW], lm[L_WRIST])


def pushup_body_line_angle(lm):
    """Push-Up form feature, LEFT-SIDE camera: shoulder-hip-ankle angle.
    ~180 deg = straight plank line; smaller = hips sagging or piked. Visible
    only from the side, which is why Push-Up moved off the front camera.
    """
    return calculate_angle(lm[L_SHOULDER], lm[L_HIP], lm[L_ANKLE])


def squat_knee_angle(lm):
    """Squat depth signal, LEFT-SIDE camera: left hip-knee-ankle angle.
    Straight legs ~170-180 deg, smaller as the squat gets deeper. From the
    side this is a true 2D angle (the front view foreshortened the thigh).
    Peak of a rep = the MINIMUM (REP_PEAK_SIGN = -1).
    """
    return calculate_angle(lm[L_HIP], lm[L_KNEE], lm[L_ANKLE])


def squat_torso_lean(lm):
    """Squat form feature, LEFT-SIDE camera: angle of the shoulder-hip line
    from vertical (0 = upright). Same formula as Lunge's torso lean. Excess
    forward lean is a common squat error and only visible from the side.
    """
    dx = lm[L_SHOULDER].x - lm[L_HIP].x
    dy = lm[L_SHOULDER].y - lm[L_HIP].y
    return abs(math.degrees(math.atan2(dx, -dy)))


def calibration_scale(exercise, lm):
    if exercise == "Push-Up":
        # Torso-length foreshortens toward zero in a front-on push-up shot
        # (the body extends in depth, not left-right), which blows up
        # displacement/scale into noise. Shoulder width doesn't foreshorten
        # the same way, so use it instead for this exercise only.
        return euclidean(lm[L_SHOULDER], lm[R_SHOULDER])
    return torso_length(lm)
def raw_reference_point(exercise, lm):
    if exercise == "Squat":
        return midpoint(lm[L_HIP], lm[R_HIP])
    else:
        return midpoint(lm[L_SHOULDER], lm[R_SHOULDER])
def feature_2_value(exercise, lm):
    """The second (non-displacement) feature for front/back exercises.

    Squat keeps its torso-lean angle. Push-Up uses elbow bend angle
    (shoulder-elbow-wrist, averaged left/right). Pull-Up has NO second feature:
    the elbow/shoulder spread ratio measured 0.35 sigma separation and AUC
    0.587 (barely above chance), and removing it raised grouped-CV accuracy
    from 70.3% to 73.5%. Every frame-local replacement candidate was either
    weaker or label-inverting (pl_elbow_asym: AUC 0.211), so Pull-Up is
    exported 1-D. Keep this in sync with _classifierFeatures in
    lib/pose_analyzer.dart.
    """
    if exercise == "Squat":
        return squat_torso_lean(lm)          # LEFT-SIDE camera
    elif exercise == "Push-Up":
        return pushup_body_line_angle(lm)    # LEFT-SIDE camera
    return None                              # Pull-Up: 1-D

# ---------------------------------------------------------------------------
# CANDIDATE features (experimental, NOT used by the app yet).
# features.csv is unchanged (feature_1/feature_2 only). The same rows are also
# written to features_candidates.csv with the extra columns below so the
# columns can be compared with grouped-by-video cross-validation BEFORE any
# of them is added to the KNN vector, the Dart code and the JSON export.
# All are calibration-free and scale-normalized. Push-Up and Pull-Up use no
# hip/knee/ankle landmarks because the app hides/ignores those for them (ML Kit
# guesses them when the legs are foreshortened or out of view).
# ---------------------------------------------------------------------------
NAN = float("nan")


def _div(a, b):
    return a / b if abs(b) > 1e-6 else NAN


def candidates_squat(lm):
    """LEFT-SIDE camera."""
    hip, knee, ankle, shoulder = lm[L_HIP], lm[L_KNEE], lm[L_ANKLE], lm[L_SHOULDER]
    trunk = euclidean(shoulder, hip)
    facing = 1.0 if lm[L_FOOT_INDEX].x >= lm[L_HEEL].x else -1.0
    return {
        "sq_shin_angle": abs(math.degrees(math.atan2(knee.x - ankle.x, ankle.y - knee.y))),
        "sq_thigh_angle": abs(math.degrees(math.atan2(knee.x - hip.x, knee.y - hip.y))),
        "sq_hip_angle": calculate_angle(shoulder, hip, knee),       # hip hinge
        "sq_hip_knee_gap": _div(knee.y - hip.y, trunk),             # depth, no baseline
        "sq_knee_fwd": _div(facing * (knee.x - ankle.x), trunk),    # knee travel past ankle
    }


def candidates_pushup(lm):
    """LEFT-SIDE camera."""
    shoulder, hip, ankle = lm[L_SHOULDER], lm[L_HIP], lm[L_ANKLE]
    elbow, wrist, ear, knee = lm[L_ELBOW], lm[L_WRIST], lm[L_EAR], lm[L_KNEE]
    line_len = euclidean(shoulder, ankle)
    dx = ankle.x - shoulder.x
    if abs(dx) < 1e-6:
        hip_sag = NAN
    else:
        y_line = shoulder.y + (hip.x - shoulder.x) * (ankle.y - shoulder.y) / dx
        # positive = hip BELOW the shoulder-ankle line (sag), negative = above (pike)
        hip_sag = _div(hip.y - y_line, line_len)
    # Torso (shoulder->hip line) angle from horizontal, in degrees. 0 = flat,
    # positive = hip lower than shoulder, negative = hip higher (pike).
    # Independent of which way the person faces.
    torso_angle = math.degrees(math.atan2(hip.y - shoulder.y, abs(hip.x - shoulder.x)))
    return {
        "pu_torso_angle": torso_angle,
        "pu_hip_sag": hip_sag,
        "pu_knee_angle": calculate_angle(hip, knee, ankle),
        "pu_head_angle": calculate_angle(ear, shoulder, hip),
        "pu_shoulder_wrist_dx": _div(abs(shoulder.x - wrist.x), line_len),  # hands under shoulders
    }


def candidates_pullup(lm):
    sw = euclidean(lm[L_SHOULDER], lm[R_SHOULDER])
    le = calculate_angle(lm[L_SHOULDER], lm[L_ELBOW], lm[L_WRIST])
    re = calculate_angle(lm[R_SHOULDER], lm[R_ELBOW], lm[R_WRIST])
    shoulder_mid = midpoint(lm[L_SHOULDER], lm[R_SHOULDER])
    wrist_mid = midpoint(lm[L_WRIST], lm[R_WRIST])
    return {
        "pl_elbow_angle": (le + re) / 2.0,
        "pl_elbow_asym": abs(le - re),
        "pl_wrist_width": _div(euclidean(lm[L_WRIST], lm[R_WRIST]), sw),
        "pl_shoulder_tilt": _div(abs(lm[L_SHOULDER].y - lm[R_SHOULDER].y), sw),
        "pl_wrist_shoulder_gap": _div(shoulder_mid.y - wrist_mid.y, sw),
    }


def candidates_lunge(lm):
    hip, knee, ankle, shoulder = lm[L_HIP], lm[L_KNEE], lm[L_ANKLE], lm[L_SHOULDER]
    trunk = euclidean(shoulder, hip)
    return {
        "lg_shin_angle": abs(math.degrees(math.atan2(knee.x - ankle.x, ankle.y - knee.y))),
        "lg_thigh_angle": abs(math.degrees(math.atan2(knee.x - hip.x, knee.y - hip.y))),
        "lg_rear_knee_angle": calculate_angle(lm[R_HIP], lm[R_KNEE], lm[R_ANKLE]),
        "lg_hip_ankle_gap": _div(ankle.y - hip.y, trunk),
    }


def candidates_plank_style(lm):
    shoulder, hip, ankle = lm[L_SHOULDER], lm[L_HIP], lm[L_ANKLE]
    elbow, ear, knee = lm[L_ELBOW], lm[L_EAR], lm[L_KNEE]
    line_len = euclidean(shoulder, ankle)
    dx = ankle.x - shoulder.x
    if abs(dx) < 1e-6:
        hip_sag = NAN
    else:
        y_line = shoulder.y + (hip.x - shoulder.x) * (ankle.y - shoulder.y) / dx
        # positive = hip BELOW the shoulder-ankle line (sag), negative = above (pike);
        # independent of which way the person faces
        hip_sag = _div(hip.y - y_line, line_len)
    return {
        "pk_hip_sag": hip_sag,
        "pk_knee_angle": calculate_angle(hip, knee, ankle),
        "pk_head_angle": calculate_angle(ear, shoulder, hip),
        "pk_shoulder_elbow_dx": _div(shoulder.x - elbow.x, line_len),
    }


def candidate_features(exercise, lm):
    """Dict of experimental columns for one frame's landmarks; never raises."""
    fn = {"Squat": candidates_squat, "Push-Up": candidates_pushup,
          "Pull-Up": candidates_pullup, "Lunge": candidates_lunge,
          "Plank": candidates_plank_style, "Side Plank": candidates_plank_style}[exercise]
    try:
        return fn(lm)
    except Exception:
        return {}


def process_video_front_back(path, exercise, label, pose, video_id):
    cap, rotate_code = open_video(path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    if not fps or fps <= 1:
        fps = 30.0  # fallback if the container doesn't report a usable fps

    displacements = []  # vertical_displacement, one entry per analyzed frame
    cands = []           # candidate-feature dicts, index-aligned with displacements
    ratios = []          # feature_2 values (ratio or angle, depending on exercise), index-aligned with displacements
    calibration_ys = []
    calibration_scales = []
    baseline_y = None
    baseline_scale = None
    total_frames = 0
    detected_frames = 0

    while cap.isOpened():
        success, frame = read_frame(cap, rotate_code)
        if not success:
            break
        total_frames += 1
        image_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        result = pose.process(image_rgb)
        if not result.pose_landmarks:
            continue
        detected_frames += 1
        lm = to_pixel_landmarks(result.pose_landmarks.landmark, frame.shape[1], frame.shape[0])

        if exercise == "Push-Up":
            # Calibration-free: no baseline needed, so every detected frame
            # after the first is usable immediately.
            displacements.append(pushup_elbow_angle(lm))
            ratios.append(feature_2_value(exercise, lm))
            cands.append(candidate_features(exercise, lm))
            continue

        if exercise == "Squat":
            # Calibration-free: same reasoning as Push-Up above.
            displacements.append(squat_knee_angle(lm))
            ratios.append(feature_2_value(exercise, lm))
            cands.append(candidate_features(exercise, lm))
            continue

        if baseline_y is None:
            ref = raw_reference_point(exercise, lm)
            scale = calibration_scale(exercise, lm)
            if scale > 1e-6:
                calibration_ys.append(ref.y)
                calibration_scales.append(scale)
            if len(calibration_ys) > CALIBRATION_FRAMES:
                calibration_ys.pop(0)
                calibration_scales.pop(0)
            if len(calibration_ys) == CALIBRATION_FRAMES:
                mean_scale = sum(calibration_scales) / len(calibration_scales)
                y_range = max(calibration_ys) - min(calibration_ys)
                if mean_scale > 1e-6 and y_range / mean_scale <= CALIBRATION_STILLNESS_FRACTION:
                    baseline_y = sum(calibration_ys) / len(calibration_ys)
                    baseline_scale = mean_scale
            continue

        ref = raw_reference_point(exercise, lm)
        scale = calibration_scale(exercise, lm)
        if scale < 1e-6 or baseline_scale < 1e-6:
            continue
        vertical_displacement = (ref.y - baseline_y) / baseline_scale
        displacements.append(vertical_displacement)
        ratios.append(feature_2_value(exercise, lm))
        cands.append(candidate_features(exercise, lm))
    cap.release()

    if exercise in ("Push-Up", "Squat"):
        baseline_y = 0.0  # sentinel: calibration-free exercises skip the "baseline never established" branch below

    if baseline_scale is not None:
        VIDEO_BASELINE_SCALES[video_id] = baseline_scale

    pct = 100.0 * detected_frames / total_frames if total_frames else 0.0
    rows = []

    if baseline_y is None:
        print(f"  {video_id}: pose detected in {detected_frames}/{total_frames} frames ({pct:.0f}%), "
              f"baseline NEVER established -- skipped")
        return rows

    if len(displacements) < 5:
        print(f"  {video_id}: pose detected in {detected_frames}/{total_frames} frames ({pct:.0f}%), "
              f"only {len(displacements)} usable post-calibration frames -- too few to detect reps, skipped")
        return rows

    signal = np.array(displacements) * REP_PEAK_SIGN[exercise]
    amplitude = float(signal.max() - signal.min())
    if amplitude < 1e-6:
        print(f"  {video_id}: pose detected in {detected_frames}/{total_frames} frames ({pct:.0f}%), "
              f"displacement never varies -- no reps detected, skipped")
        return rows

    min_distance = max(int(fps * MIN_REP_SPACING_SECONDS), 3)
    peak_idx, _ = find_peaks(
        signal,
        prominence=MIN_REP_PROMINENCE_FRACTION * amplitude,
        distance=min_distance,
    )

    used_fallback = False
    if len(peak_idx) == 0:
        # Default thresholds are tuned for a "typical" clip length/fps. A
        # short clip in particular may not be able to fit two peaks at the
        # default minimum spacing even though the signal clearly moves --
        # retry once with both requirements halved before giving up.
        relaxed_prominence = 0.5 * MIN_REP_PROMINENCE_FRACTION * amplitude
        relaxed_distance = max(min_distance // 2, 3)
        peak_idx, _ = find_peaks(signal, prominence=relaxed_prominence, distance=relaxed_distance)
        used_fallback = len(peak_idx) > 0

    for j, i in enumerate(peak_idx):
        i = int(i)
        # whole-rep range of motion: peak vs the lowest point between the
        # neighbouring peaks (or clip ends). Same units as feature_1.
        lo = int(peak_idx[j - 1]) if j > 0 else 0
        hi = int(peak_idx[j + 1]) if j + 1 < len(peak_idx) else len(signal) - 1
        extras = dict(cands[i])
        extras["rep_rom"] = float(signal[i] - signal[lo:hi + 1].min())
        # Pull-Up is 1-D: feature_2_value returns None, which pandas writes as
        # an empty cell. export_for_app.py's example_features() skips empty
        # feature_N columns, so the exported vector is correctly length 1.
        ratio = ratios[i]
        rows.append([exercise, label, displacements[i],
                     "" if ratio is None else ratio, video_id, extras])

    if exercise in ("Push-Up", "Squat") and len(displacements) >= 5:
        # Rest value = before any rep starts, i.e. before the first detected
        # peak's rep began. Diagnostic only -- not fed to the classifier --
        # used to pick real engage/down/up thresholds for the live app
        # instead of guessing them.
        first_peak = int(peak_idx[0]) if len(peak_idx) else len(displacements)
        pre_rep = displacements[: max(first_peak - min_distance // 2, 1)]
        if pre_rep:
            VIDEO_REST_VALUES[video_id] = float(np.median(pre_rep))

    fallback_note = " (found via relaxed prominence/spacing fallback)" if used_fallback else ""
    print(f"  {video_id}: pose detected in {detected_frames}/{total_frames} frames ({pct:.0f}%), "
          f"{len(rows)} rep(s) detected{fallback_note}")
    if len(rows) == 0:
        print(f"    WARNING: 0 reps detected even with relaxed thresholds -- clip is likely too "
              f"short/noisy for peak-finding as-is (usable post-calibration frames: "
              f"{len(displacements)}, signal amplitude: {amplitude:.3f}); inspect this clip manually")
    VIDEO_DETECTION_STATS[video_id] = {
        "exercise": exercise, "label": label,
        "total_frames": total_frames, "detected_frames": detected_frames,
        "rows": len(rows), "detection_pct": round(pct, 1),
    }
    return rows
def process_video_side_view(path, exercise, label, pose, video_id):
    cap, rotate_code = open_video(path)
    rows = []
    frame_skip = 5
    frame_idx = 0
    total_frames = 0
    detected_frames = 0
    while cap.isOpened():
        success, frame = read_frame(cap, rotate_code)
        if not success:
            break
        frame_idx += 1
        if frame_idx % frame_skip != 0:
            continue
        total_frames += 1
        image_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        result = pose.process(image_rgb)
        if not result.pose_landmarks:
            continue
        detected_frames += 1
        lm = to_pixel_landmarks(result.pose_landmarks.landmark, frame.shape[1], frame.shape[0])
        if exercise == "Lunge":
            features = features_lunge(lm)
        else:
            features = features_plank_style(lm)
        rows.append([exercise, label] + features + [video_id, candidate_features(exercise, lm)])
    cap.release()
    if total_frames > 0:
        pct = 100.0 * detected_frames / total_frames
        print(f"  {video_id}: pose detected in {detected_frames}/{total_frames} sampled frames ({pct:.0f}%), "
              f"{len(rows)} usable rows")
    VIDEO_DETECTION_STATS[video_id] = {
        "exercise": exercise, "label": label,
        "total_frames": total_frames, "detected_frames": detected_frames,
        "rows": len(rows),
        "detection_pct": round(100.0 * detected_frames / total_frames, 1) if total_frames else 0.0,
    }
    return rows
def main():
    all_rows = []
    with mp_pose.Pose(static_image_mode=False) as pose:
        for exercise in os.listdir(DATASET_DIR):
            exercise_path = os.path.join(DATASET_DIR, exercise)
            if not os.path.isdir(exercise_path):
                continue
            for label in ["correct", "incorrect"]:
                label_path = os.path.join(exercise_path, label)
                if not os.path.isdir(label_path):
                    continue
                for filename in os.listdir(label_path):
                    if not filename.lower().endswith((".mp4", ".mov", ".avi")):
                        continue
                    video_path = os.path.join(label_path, filename)
                    # video_id groups all rows from one source video together so
                    # train_and_validate.py can split by video instead of by frame.
                    video_id = f"{exercise}/{label}/{filename}"
                    print(f"Processing {video_path} ...")
                    if exercise in FRONT_BACK_EXERCISES:
                        rows = process_video_front_back(video_path, exercise, label, pose, video_id)
                    elif exercise in SIDE_VIEW_EXERCISES:
                        rows = process_video_side_view(video_path, exercise, label, pose, video_id)
                    else:
                        print(f"  Skipping unrecognized exercise folder: {exercise}")
                        continue
                    if len(rows) == 0:
                        print(f"  WARNING: 0 usable rows from {video_path} -- it will contribute nothing to training")
                    all_rows.extend(rows)
    # Columns: exercise, label, feature_1, feature_2, [feature_3], video_id, extras.
    # Lunge emits 5 features; Plank/Side Plank emit 3; the rest emit 2.
    max_features = max((len(r) for r in all_rows), default=6) - 3  # minus exercise,label,video_id,extras
    feature_cols = [f"feature_{i+1}" for i in range(max_features)]
    columns = ["exercise", "label"] + feature_cols + ["video_id", "extras"]
    # Rows are ragged: 2-feature exercises emit 6 fields, 3-feature (Plank/Side
    # Plank) emit 7, 5-feature (Lunge) emit 9. Pad every short row with None so
    # pandas can build a rectangular frame instead of raising a column-count
    # mismatch.
    ncols = len(columns)
    # Rows are built as [exercise, label, f1, f2, (f3), video_id, extras].
    # 2-feature rows have 6 fields, 3-feature rows have 7. The missing field for
    # short rows is the optional feature_3, which sits BEFORE video_id/extras --
    # so pad it in the middle, not at the end, or video_id/extras shift left and
    # video_id ends up empty. Insert the missing feature slot right before the
    # last two fields (video_id, extras).
    padded = []
    for r in all_rows:
        if len(r) == ncols:
            padded.append(r)
        else:
            missing = ncols - len(r)
            head = r[:-2]                       # exercise, label, existing features
            tail = r[-2:]                       # video_id, extras
            padded.append(head + [None] * missing + tail)
    df = pd.DataFrame(padded, columns=columns)

    rest = pd.Series(VIDEO_REST_VALUES, name="rest_value")
    if not rest.empty:
        rest_df = rest.rename_axis("video_id").reset_index()
        rest_df["exercise"] = rest_df["video_id"].str.split("/").str[0]
        rest_df["label"] = rest_df["video_id"].str.split("/").str[1]
        rest_df.to_csv("rest_values.csv", index=False)  # for setting real UI phase thresholds

    # Per-clip detection stats (diagnostic only, not used for training).
    if VIDEO_DETECTION_STATS:
        stats_df = pd.DataFrame.from_dict(VIDEO_DETECTION_STATS, orient="index")
        stats_df.index.name = "video_id"
        stats_df.reset_index().to_csv("detection_stats.csv", index=False)
        print(f"\nSaved per-clip detection stats to detection_stats.csv "
              f"({len(stats_df)} clips) -- inspect this to see why row counts differ "
              f"across clips of the same exercise (low detection_pct = frames dropped).")

    # Baseline-scale gate (front/back exercises only)
    scales = pd.Series(VIDEO_BASELINE_SCALES, name="baseline_scale")
    if not scales.empty:
        scale_df = scales.rename_axis("video_id").reset_index()
        scale_df["exercise"] = scale_df["video_id"].str.split("/").str[0]
        scale_df.to_csv("baseline_scales.csv", index=False)  # for manual inspection
        medians = scale_df.groupby("exercise")["baseline_scale"].median()
        bad = scale_df[scale_df["baseline_scale"] < scale_df["exercise"].map(medians) * MIN_BASELINE_SCALE_FRACTION]
        if len(bad) > 0:
            print(f"\nBaseline-scale gate: dropping {len(bad)} video(s) with scale < "
                  f"{MIN_BASELINE_SCALE_FRACTION:.0%} of their exercise's median:")
            for _, r in bad.iterrows():
                print(f"  {r['video_id']}: scale={r['baseline_scale']:.4f} "
                      f"(median {medians[r['exercise']]:.4f})")
            df = df[~df["video_id"].isin(bad["video_id"])]

    # Outlier trim (per exercise, all feature columns present in this run).
    all_feature_cols = [c for c in df.columns if c.startswith("feature_")]
    keep = pd.Series(True, index=df.index)
    for ex, g in df.groupby("exercise"):
        for col in all_feature_cols:
            # feature_3 is None for 2-feature exercises; skip empty columns so
            # mean() doesn't choke on an all-None series.
            s = pd.to_numeric(g[col], errors="coerce")
            valid = s.dropna()
            if valid.empty:
                continue
            m, sd = valid.mean(), valid.std()
            if sd and sd > 0:
                keep[g.index[(s - m).abs() > OUTLIER_STD * sd]] = False
    dropped = int((~keep).sum())
    if dropped:
        print(f"\nOutlier trim: dropping {dropped} row(s) beyond {OUTLIER_STD:.0f} std:")
        print(df[~keep].groupby("exercise").size())
    df = df[keep]
    # features.csv keeps its original columns (downstream scripts unaffected);
    # features_candidates.csv = same rows + experimental columns.
    base = df.drop(columns="extras")
    base.to_csv(OUTPUT_CSV, index=False)
    extras_df = pd.DataFrame(df["extras"].tolist(), index=df.index)
    pd.concat([base, extras_df], axis=1).to_csv("features_candidates.csv", index=False)
    df = base
    print(f"\nSaved {len(df)} labeled feature rows to {OUTPUT_CSV}")
    print(df.groupby(["exercise", "label"]).size())
    print(f"\nUnique source videos per exercise/label:")
    # Cast to str so any residual None/NaN video_id doesn't break nunique().
    print(df.assign(video_id=df["video_id"].astype(str))
            .groupby(["exercise", "label"])["video_id"].nunique())
if __name__ == "__main__":
    main()
