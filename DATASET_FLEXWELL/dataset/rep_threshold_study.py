# -*- coding: utf-8 -*-
"""
rep_threshold_study.py -- are we LOSING reps, or are the clips single-rep?

Run this when an exercise has suspiciously few rows (Squat/Push-Up/Pull-Up do)
to decide between two possible causes before re-recording anything:

  A) the extractor's rep-detection thresholds are too strict and dropping real
     reps  -> fix the thresholds, no re-recording needed
  B) the clips genuinely contain ~1 rep -> re-record multi-rep clips

It re-runs the extractor's own prominence/spacing rep-detection on each video
at three strictness levels (default / relaxed / aggressive). If "aggressive"
finds many more reps than "default", it's cause (A). If they're about equal,
it's cause (B) -- the footage simply has one rep and no threshold can invent
more.

Typical use:
    python rep_threshold_study.py Squat 6      # first 6 clips per class
    python rep_threshold_study.py Push-Up 8

Finding (Oct 2026): Squat and Push-Up clips are 13-30 sampled frames with a
tiny displacement range -- genuinely single-rep. Aggressive thresholds found
essentially nothing extra, confirming cause (B). Re-recording multi-rep clips
is the only lever that raises accuracy for these exercises.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scipy.signal import find_peaks

DATASET = os.path.dirname(os.path.abspath(__file__))
import simulate_form_check as S
import cv2
import mediapipe as mp

REP_PEAK_SIGN = {"Squat": -1, "Push-Up": -1, "Pull-Up": -1, "Lunge": -1}
SAMPLE_EVERY = 5


def displacement_series(path, ex):
    """Reproduce the extractor's per-frame displacement signal."""
    fn = S.FEATS[ex]
    cap = cv2.VideoCapture(path)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30
    disp = []
    with mp.solutions.pose.Pose(static_image_mode=False, model_complexity=1,
                                min_detection_confidence=0.5) as pose:
        idx = 0
        while cap.isOpened():
            ok, frame = cap.read()
            if not ok:
                break
            idx += 1
            if idx % SAMPLE_EVERY != 0:
                continue
            res = pose.process(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
            if not res.pose_landmarks:
                continue
            lm = res.pose_landmarks.landmark
            need = [S.L_SHOULDER, S.L_HIP, S.L_KNEE, S.L_ANKLE]
            if ex == "Push-Up":
                need = [S.L_SHOULDER, S.L_ELBOW, S.L_WRIST, S.L_HIP, S.L_ANKLE]
            if ex == "Pull-Up":
                need = [S.L_SHOULDER, S.R_SHOULDER, S.L_ELBOW, S.R_ELBOW]
            if any(lm[i].visibility < 0.6 for i in need):
                continue
            # vertical displacement of the reference point (hip for squat,
            # shoulder-mid for push-up/pullup), matching the extractor
            if ex == "Squat":
                y = (lm[S.L_HIP].y + lm[S.R_HIP].y) / 2
            else:
                y = (lm[S.L_SHOULDER].y + lm[S.R_SHOULDER].y) / 2
            disp.append(y)
    cap.release()
    return np.array(disp), fps


def count_reps(signal, fps, prominence_frac, spacing_s):
    if len(signal) < 5:
        return 0
    sig = signal * REP_PEAK_SIGN.get("Squat", -1)
    amp = sig.max() - sig.min()
    if amp < 1e-6:
        return 0
    dist = max(int(fps / SAMPLE_EVERY * spacing_s), 3)
    idx, _ = find_peaks(sig, prominence=prominence_frac * amp, distance=dist)
    return len(idx)


def main():
    ex = sys.argv[1] if len(sys.argv) > 1 else "Squat"
    nvid = int(sys.argv[2]) if len(sys.argv) > 2 else 6
    print(f"=== {ex}: reps detectable at 3 threshold levels ===")
    print(f"{'video':26s} {'frames':>6s} {'range':>6s} | {'default':>8s} "
          f"{'relaxed':>8s} {'aggressive':>10s}")
    print("-" * 74)
    tot = [0, 0, 0]
    for lab in ["correct", "incorrect"]:
        d = os.path.join(DATASET, ex, lab)
        if not os.path.isdir(d):
            continue
        vids = sorted(f for f in os.listdir(d)
                      if f.lower().endswith((".mov", ".mp4", ".avi")))[:nvid]
        for v in vids:
            sig, fps = displacement_series(os.path.join(d, v), ex)
            if len(sig) < 5:
                print(f"{v[:26]:26s} {len(sig):6d} {'--':>6s} | no signal")
                continue
            rng = float(sig.max() - sig.min())
            # default: prominence 0.15, spacing 0.5s  (sample_every=5)
            dd = count_reps(sig, fps * SAMPLE_EVERY, 0.15, 0.5)
            rr = count_reps(sig, fps * SAMPLE_EVERY, 0.075, 0.25)
            aa = count_reps(sig, fps * SAMPLE_EVERY, 0.05, 0.20)
            tot[0] += dd
            tot[1] += rr
            tot[2] += aa
            print(f"{v[:26]:26s} {len(sig):6d} {rng:6.2f} | {dd:8d} {rr:8d} {aa:10d}")
    print("-" * 74)
    print(f"{'TOTAL':26s} {'':6s} {'':6s} | {tot[0]:8d} {tot[1]:8d} {tot[2]:10d}")
    print()
    print("If 'aggressive' >> 'default', thresholds are dropping real reps.")
    print("If aggressive ~= default, the clips genuinely contain ~1 rep.")


if __name__ == "__main__":
    main()
