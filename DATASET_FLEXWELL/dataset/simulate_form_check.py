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
    smy = (lm[L_SHOULDER].y + lm[R_SHOULDER].y) / 2
    hmy = (lm[L_HIP].y + lm[R_HIP].y) / 2
    disp = (hmy - smy)  # vertical shoulder displacement proxy
    ed, sd = dist(lm[L_ELBOW], lm[R_ELBOW]), dist(lm[L_SHOULDER], lm[R_SHOULDER])
    ratio = ed / sd if sd > 1e-6 else 0.0
    return [disp, ratio]


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


def run_video(path, ex, limit_frames=None):
    mp_pose = mp.solutions.pose
    cap = cv2.VideoCapture(path)
    model = Model(ex)
    smoother = Smoother()
    fn = FEATS[ex]
    verdicts, ood_frames, reliable = [], 0, 0
    idx = 0
    with mp_pose.Pose(static_image_mode=False, model_complexity=1,
                      min_detection_confidence=0.5) as pose:
        while cap.isOpened():
            ok, frame = cap.read()
            if not ok:
                break
            idx += 1
            if limit_frames and idx > limit_frames:
                break
            if idx % SAMPLE_EVERY != 0:
                continue
            h, w = frame.shape[:2]
            res = pose.process(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
            if not res.pose_landmarks:
                continue
            lm = res.pose_landmarks.landmark
            need = [L_SHOULDER, L_HIP, L_KNEE, L_ANKLE]
            if ex == "Push-Up":
                need = [L_SHOULDER, L_ELBOW, L_WRIST, L_HIP, L_ANKLE]
            if ex == "Pull-Up":
                need = [L_SHOULDER, R_SHOULDER, L_ELBOW, R_ELBOW]
            if any(lm[i].visibility < 0.6 for i in need):
                continue
            reliable += 1
            raw = fn(lm)
            v, is_ood = model.classify(raw)
            if is_ood:
                ood_frames += 1
                continue
            if v is None:
                continue
            verdicts.append(smoother.add(v))
    cap.release()
    if not verdicts:
        return None, reliable, ood_frames
    # session verdict = majority of engaged frames
    return (sum(verdicts) * 2 >= len(verdicts)), reliable, ood_frames


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
                verdict, rel, ood = run_video(os.path.join(d, v), ex)
                tot += 1
                grand[lab] += 1
                if verdict is None:
                    print(f"    {v[:34]:34s} -> no verdict (rel={rel}, ood={ood})")
                    continue
                pred = "correct" if verdict else "incorrect"
                ok = pred == lab
                hit += 1 if ok else 0
                grand_ok[lab] += 1 if ok else 0
                mark = "OK " if ok else "MISS"
                print(f"    {mark} {v[:34]:34s} -> {pred:9s} (rel={rel:4d}, ood={ood:3d})")
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
