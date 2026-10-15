# -*- coding: utf-8 -*-
"""
End-to-end simulation of the app's form-checking pipeline, on real video.

Mirrors exactly what the phone does:
  ML Kit pose detection      -> mediapipe.solutions.pose (same backend)
  feature extraction         -> the SAME formulas as extract_features.py
  z-score normalisation      -> the SAME mean/std as knn_training_data.json
  KNN classification (k=5)   -> the SAME model the app ships
  OOD guard                  -> the SAME oodRadius the app ships
  FormSmoother (window 5,min3)-> the SAME smoother as the app

For each video we replay frame-by-frame, compute the per-frame verdict, smooth
it, and compare the session verdict to the ground-truth label. This tests the
form-checking logic the way the app would see it -- the one thing the emulator
can't (no real person in frame).
"""
import ast
import json
import math
import os
import sys

import cv2
import mediapipe as mp
import numpy as np

DATASET = r"C:\Users\Janelyn\Downloads\Flutter\Flexwell\flexwell_flutter\DATASET_FLEXWELL\dataset"
MODEL = json.load(open(r"C:\Users\Janelyn\Downloads\Flutter\Flexwell\flexwell_flutter\assets\knn_training_data.json"))

# MediaPipe landmark indices (same as extract_features.py)
L_SHOULDER, R_SHOULDER = 11, 12
L_ELBOW, R_ELBOW = 13, 14
L_WRIST, R_WRIST = 15, 16
L_HIP, R_HIP = 23, 24
L_KNEE, R_KNEE = 25, 26
L_ANKLE, R_ANKLE = 27, 28

SAMPLE_EVERY = 5  # same stride as the extractor


def angle(a, b, c):
    ba = np.array([a.x - b.x, a.y - b.y])
    bc = np.array([c.x - b.x, c.y - b.y])
    denom = np.linalg.norm(ba) * np.linalg.norm(bc)
    if denom < 1e-9:
        return 0.0
    cosv = np.clip(np.dot(ba, bc) / denom, -1.0, 1.0)
    return math.degrees(math.acos(cosv))


def dist(a, b):
    return math.hypot(a.x - b.x, a.y - b.y)


def torso_len(lm):
    sm = type("P", (), {"x": (lm[L_SHOULDER].x + lm[R_SHOULDER].x) / 2,
                        "y": (lm[L_SHOULDER].y + lm[R_SHOULDER].y) / 2})
    hm = type("P", (), {"x": (lm[L_HIP].x + lm[R_HIP].x) / 2,
                        "y": (lm[L_HIP].y + lm[R_HIP].y) / 2})
    return dist(sm, hm)


def div(a, b):
    return a / b if abs(b) > 1e-6 else float("nan")


# ---- feature vectors: MUST match extract_features.py / pose_analyzer.dart ----
def f_lunge(lm):
    s, h, k, a = lm[L_SHOULDER], lm[L_HIP], lm[L_KNEE], lm[L_ANKLE]
    knee = angle(h, k, a)
    torso = abs(math.degrees(math.atan2(s.x - h.x, -(s.y - h.y))))
    shin = abs(math.degrees(math.atan2(k.x - a.x, a.y - k.y)))
    gap = div(a.y - h.y, dist(s, h))
    thigh = abs(math.degrees(math.atan2(k.x - h.x, k.y - h.y)))
    return [knee, torso, shin, gap, thigh]


def f_plank(lm):
    s, h, a, e = lm[L_SHOULDER], lm[L_HIP], lm[L_ANKLE], lm[L_ELBOW]
    back = angle(s, h, a)
    ll = dist(s, a)
    if ll < 1e-6:
        hipdev = 0.0
    else:
        num = abs((a.y - s.y) * h.x - (a.x - s.x) * h.y + a.x * s.y - a.y * s.x)
        hipdev = num / ll / ll
    dx = div(abs(s.x - e.x), ll)
    return [back, hipdev, dx]


def f_squat(lm):
    s, h, k, a = lm[L_SHOULDER], lm[L_HIP], lm[L_KNEE], lm[L_ANKLE]
    knee = angle(h, k, a)
    torso = abs(math.degrees(math.atan2(s.x - h.x, -(s.y - h.y))))
    return [knee, torso]


def f_pushup(lm):
    s, h, a = lm[L_SHOULDER], lm[L_HIP], lm[L_ANKLE]
    elbow = angle(s, lm[L_ELBOW], lm[L_WRIST])
    body = angle(s, h, a)
    return [elbow, body]


def f_pullup(lm):
    # Pull-Up is 1-D since the dead elbow/shoulder ratio feature was removed
    # (0.35 sigma separation, AUC 0.587; removing it raised grouped-CV accuracy
    # 67.3% -> 74.8%). The app ships mean length 1, so returning 2 values here
    # would feed a 2-vector into a 1-D model and make every distance garbage.
    smy = (lm[L_SHOULDER].y + lm[R_SHOULDER].y) / 2
    hmy = (lm[L_HIP].y + lm[R_HIP].y) / 2
    return [(hmy - smy)]  # vertical shoulder displacement only


FEATS = {"Lunge": f_lunge, "Plank": f_plank, "Side Plank": f_plank,
         "Squat": f_squat, "Push-Up": f_pushup, "Pull-Up": f_pullup}


class Model:
    def __init__(self, ex):
        d = MODEL[ex]
        self.mean = np.array(d["mean"], float)
        self.std = np.array(d["std"], float)
        # stored examples are RAW; z-score them once at load (the Dart app does
        # the same via the scaler). Comparing raw f against a z-scored q is the
        # bug that made every frame look OOD.
        zs = np.where(self.std == 0, 1, self.std)
        self.ex = [(((np.array(e["features"], float) - self.mean) / zs),
                    1 if e["label"] == "correct" else 0)
                   for e in d["examples"]]
        self.ood = d.get("oodRadius")

    def classify(self, raw):
        v = np.array(raw, float)
        if not np.all(np.isfinite(v)) or len(v) != len(self.mean):
            return None, False
        q = (v - self.mean) / np.where(self.std == 0, 1, self.std)
        ds = sorted((np.sqrt(((f - q) ** 2).sum()), lab) for f, lab in self.ex)
        nearest = ds[0][0]
        if self.ood is not None and nearest > self.ood:
            return None, True  # out of distribution
        votes = sum(lab for _, lab in ds[:5])
        return (votes > 2.5), False


class Smoother:
    def __init__(self, window=5, minf=3):
        self.w, self.mf, self.q, self.c = window, minf, [], 0

    def add(self, ok):
        self.q.append(ok)
        if ok:
            self.c += 1
        if len(self.q) > self.w:
            if self.q.pop(0):
                self.c -= 1
        if len(self.q) < self.mf:
            return ok
        return self.c >= (len(self.q) - self.c)


# ---- engage gate: MUST mirror _isEngagedInMovement() in camera_screen.dart ----
# The app only classifies frames where the user is actually in a rep. Without
# this the simulator votes over resting frames too, which structurally inflates
# correct-form scores (standing still looks like good form).
LUNGE_ENGAGE = 150.0     # repSignal <= 150  (knee angle)
PULLUP_ENGAGE = -0.12    # repSignal <= -0.12 (displacement, +y = downward)
DEFAULT_ENGAGE = 0.12    # repSignal >= 0.12  (normalized displacement)


def is_engaged(ex, rep_signal):
    """Same comparisons as _CameraScreenState._isEngagedInMovement()."""
    if ex == "Lunge":
        return rep_signal <= LUNGE_ENGAGE
    if ex == "Pull-Up":
        return rep_signal <= PULLUP_ENGAGE
    return rep_signal >= DEFAULT_ENGAGE


# ---- rep-peak alignment: MUST mirror extract_features.py's row writing ----
# The model is trained on ONE row per rep, sampled at the rep PEAK, found with
# the trainer's exact parameters (extract_features.py:511-525):
#     min_distance = max(int(fps * MIN_REP_SPACING_SECONDS), 3)
#     prominence   = MIN_REP_PROMINENCE_FRACTION * amplitude
# Both are in FRAME units on the full-resolution signal. Two earlier mistakes
# made the verdict meaningless: (1) classifying every frame instead of peaks,
# (2) sampling every 5th frame, which cut the peak finder's resolution to 1/5
# so prominence fired on the wrong frames. This now matches the trainer.
MIN_REP_PROMINENCE_FRACTION = 0.15  # extract_features.py:128
MIN_REP_SPACING_SECONDS = 0.5       # extract_features.py:129
REP_PEAK_SIGN = {"Squat": -1, "Push-Up": -1, "Pull-Up": -1}


def find_rep_peaks(signal, ex, fps):
    """Identical logic to the trainer's peak detection."""
    from scipy.signal import find_peaks
    s = np.asarray(signal, float) * REP_PEAK_SIGN.get(ex, 1)
    if len(s) < 5:
        return []
    amplitude = float(s.max() - s.min())
    if amplitude < 1e-6:
        return []
    min_distance = max(int(fps * MIN_REP_SPACING_SECONDS), 3)
    pk, _ = find_peaks(
        s,
        prominence=MIN_REP_PROMINENCE_FRACTION * amplitude,
        distance=min_distance,
    )
    if len(pk) == 0:
        # Relaxed fallback, exactly as the trainer does it.
        relaxed_prominence = 0.5 * MIN_REP_PROMINENCE_FRACTION * amplitude
        relaxed_distance = max(min_distance // 2, 3)
        pk, _ = find_peaks(s, prominence=relaxed_prominence,
                           distance=relaxed_distance)
    return [int(i) for i in pk]


def run_video(path, ex, limit_frames=None):
    mp_pose = mp.solutions.pose
    # Use the trainer's video opener so rotation metadata is applied identically.
    import extract_features as EF
    cap, rotate_code = EF.open_video(path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    if not fps or fps != fps or fps < 1:
        fps = 30.0  # same fallback the trainer uses
    model = Model(ex)
    smoother = Smoother()
    fn = FEATS[ex]

    # ---- calibration, ported verbatim from process_video_front_back() ----
    # Squat and Push-Up are calibration-free. Pull-Up is NOT: its feature_1 is
    # (ref.y - baseline_y) / baseline_scale, so without this the displacement
    # is in raw pixels (~600) instead of normalized units (~-0.4), the peak
    # finder sees no signal, and every clip reports "no verdict".
    needs_calibration = ex not in ("Squat", "Push-Up")
    calib_ys, calib_scales = [], []
    baseline_y = baseline_scale = None

    verdicts, ood_frames, reliable = [], 0, 0
    frames_feat1 = []      # feature_1 per reliable frame, for peak finding
    frames_raw = []        # full feature vector per reliable frame
    idx = 0
    # Pose config MUST match extract_features.py:607 exactly:
    #     mp_pose.Pose(static_image_mode=False)
    # The simulator previously forced model_complexity=1 and
    # min_detection_confidence=0.5, which loads a DIFFERENT model. On
    # Squat/correct/IMG_0356.mov that picked frame 43 (knee 45.4 deg) where the
    # trainer stored knee 39.9 deg -- different landmarks, so a different rep
    # peak and a wrong verdict. Same clip, same rep, different model.
    with mp_pose.Pose(static_image_mode=False) as pose:
        while cap.isOpened():
            ok, frame = cap.read()
            if not ok:
                break
            if rotate_code is not None:
                frame = cv2.rotate(frame, rotate_code)
            idx += 1
            if limit_frames and idx > limit_frames:
                break
            # The extractor processes EVERY frame (no stride). Sampling here
            # gave the peak finder 1/5 the temporal resolution, so
            # prominence=0.15*amplitude fired on the wrong frames and the
            # session verdict was meaningless. Match the trainer exactly.
            h, w = frame.shape[:2]
            res = pose.process(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
            if not res.pose_landmarks:
                continue
            # Convert to PIXEL landmarks exactly as the trainer does
            # (extract_features.py:170). MediaPipe returns x/y normalized
            # SEPARATELY by width and height, so on a non-square frame angles
            # are anisotropically distorted -- and ML Kit on the phone returns
            # isotropic pixels. Passing raw normalized landmarks here made every
            # angle wrong (knee min 45.4 deg where the trainer measures 40.5).
            lm = EF.to_pixel_landmarks(res.pose_landmarks.landmark, w, h)
            # No visibility gate here: process_video_front_back() accepts every
            # detected frame. Adding one would filter a different population
            # than training, and _Pt has no .visibility attribute anyway.

            if needs_calibration:
                if baseline_y is None:
                    ref = EF.raw_reference_point(ex, lm)
                    scale = EF.calibration_scale(ex, lm)
                    if scale > 1e-6:
                        calib_ys.append(ref.y)
                        calib_scales.append(scale)
                    if len(calib_ys) > EF.CALIBRATION_FRAMES:
                        calib_ys.pop(0)
                        calib_scales.pop(0)
                    if len(calib_ys) == EF.CALIBRATION_FRAMES:
                        mean_scale = sum(calib_scales) / len(calib_scales)
                        y_range = max(calib_ys) - min(calib_ys)
                        if (mean_scale > 1e-6 and
                                y_range / mean_scale <= EF.CALIBRATION_STILLNESS_FRACTION):
                            baseline_y = sum(calib_ys) / len(calib_ys)
                            baseline_scale = mean_scale
                    continue
                # Calibrated: feature_1 is normalized vertical displacement.
                ref = EF.raw_reference_point(ex, lm)
                scale = EF.calibration_scale(ex, lm)
                if scale < 1e-6 or baseline_scale < 1e-6:
                    continue
                disp = (ref.y - baseline_y) / baseline_scale
                reliable += 1
                frames_feat1.append(disp)
                frames_raw.append([disp] + list(fn(lm)[1:]))
                continue

            reliable += 1
            raw = fn(lm)
            frames_feat1.append(raw[0])
            frames_raw.append(raw)
    cap.release()

    # Find rep peaks with the trainer's EXACT parameters (frame units, real fps).
    peak_idx = find_rep_peaks(frames_feat1, ex, fps)
    for i in peak_idx:
        raw = frames_raw[i]
        v, is_ood = model.classify(raw)
        if is_ood:
            ood_frames += 1
            continue
        if v is None:
            continue
        verdicts.append(smoother.add(v))

    if not verdicts:
        return None, reliable, ood_frames, len(verdicts)
    # session verdict = majority of rep-peak frames
    return (sum(verdicts) * 2 >= len(verdicts)), reliable, ood_frames, len(verdicts)


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    per_ex = int(sys.argv[2]) if len(sys.argv) > 2 else 5  # videos per class
    exercises = [which] if which != "all" else list(FEATS.keys())
    grand = {"correct": 0, "incorrect": 0}
    grand_ok = {"correct": 0, "incorrect": 0}
    for ex in exercises:
        print(f"\n=== {ex} ===")
        for lab in ["correct", "incorrect"]:
            d = os.path.join(DATASET, ex, lab)
            vids = sorted(f for f in os.listdir(d) if f.lower().endswith((".mov", ".mp4", ".avi")))
            vids = vids[:per_ex]
            hit = tot = 0
            for v in vids:
                verdict, rel, ood, eng = run_video(os.path.join(d, v), ex)
                tot += 1
                grand[lab] += 1
                if verdict is None:
                    print(f"    {v[:34]:34s} -> no verdict (rel={rel}, ood={ood}, engaged={eng})")
                    continue
                pred = "correct" if verdict else "incorrect"
                ok = pred == lab
                hit += 1 if ok else 0
                grand_ok[lab] += 1 if ok else 0
                mark = "OK " if ok else "MISS"
                print(f"    {mark} {v[:34]:34s} -> {pred:9s} "
                      f"(rel={rel:4d}, ood={ood:3d}, engaged={eng:4d})")
            if tot:
                print(f"  {ex}/{lab}: {hit}/{tot} correct = {hit/tot*100:.0f}%")
    print("\n" + "=" * 50)
    print("OVERALL")
    for lab in ["correct", "incorrect"]:
        if grand[lab]:
            print(f"  {lab:10s}: {grand_ok[lab]}/{grand[lab]} = {grand_ok[lab]/grand[lab]*100:.0f}%")
    tg = sum(grand.values())
    if tg:
        tok = sum(grand_ok.values())
        print(f"  {'TOTAL':10s}: {tok}/{tg} = {tok/tg*100:.0f}%")


if __name__ == "__main__":
    main()
