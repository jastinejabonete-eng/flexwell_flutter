"""
export_for_app.py
Converts features.csv into a JSON file the mobile app can bundle as an
asset and use directly for KNN inference on-device.

Since the features are on very different numeric scales for some exercises
(e.g. an angle in degrees vs. a ratio in 0.0-1.0), this script also computes
and saves the per-exercise mean/std of each feature, so the Dart-side
classifier can apply the SAME z-score normalization at inference time that
train_and_validate.py used for validation. Without this, one feature could
silently dominate the distance calculation on-device.

Feature width: most exercises emit 2 features; Plank and Side Plank emit 3
(the third is pk_shoulder_elbow_dx, mirrored on the Dart side in
pose_analyzer.dart _plankStyleFeatures). The width is detected from the CSV
row structure, so this script adapts automatically. The Dart side MUST send
the same number of features it expects -- the sanity check at the bottom
warns loudly if an exercise's exported width looks unexpected.
"""

import csv
import json
import math
import os
import sys
from pathlib import Path

# Optional overrides (2026-11-06 label-denoise trial):
#   python export_for_app.py [input.csv] [output.json]
# Defaults keep the original behaviour: features.csv -> knn_training_data.json.
INPUT_CSV = Path(sys.argv[1]) if len(sys.argv) > 1 else DATASET_DIR / "features.csv"
OUTPUT_JSON = Path(sys.argv[2]) if len(sys.argv) > 2 else DATASET_DIR / "knn_training_data.json"

# Every feature_N column that may exist. Lunge emits 5, Plank/Side Plank 3,
# the rest 2 -- so this must cover the widest exercise, not a fixed 3.
# example_features() keeps only the columns actually present and non-empty for
# each row, so shorter exercises are unaffected.
FEATURE_COLS = ["feature_1", "feature_2", "feature_3", "feature_4", "feature_5"]
DATASET_DIR = Path(__file__).resolve().parent


def _live_video_dists(exercise, model, max_videos=4, sample_every=5, max_frames=200):
    """Nearest-training-example distances for real frames, measured from video.

    Used to calibrate/validate the OOD radius against what real reps actually
    look like to the app. Replays a few training clips through mediapipe (the
    same backend ML Kit uses) and returns, for every reliable frame, its
    distance to the closest z-scored training example.

    These videos are the ground truth for "what a real rep looks like to the
    app". The caller takes the 99th percentile as the radius, which holds
    ~0-2% of live frames outside for every exercise.

    Returns an empty list if mediapipe/opencv are unavailable or no video
    exists, in which case the caller keeps whatever radius it already had.
    """
    try:
        import cv2
        import mediapipe as mp
    except ImportError:
        print(f"       {exercise}: mediapipe/opencv unavailable, "
              f"keeping held-out radius")
        return None

    import random
    rng = random.Random(0)
    mean = model["mean"]
    std = model["std"]
    dims = len(mean)

    def zs(v):
        return [(v[i] - mean[i]) / (std[i] if std[i] else 1.0) for i in range(dims)]

    ztrain = [zs(e["features"]) for e in model["examples"]]

    # Same landmark feature extractors the app uses (pose_analyzer.dart).
    L_SHOULDER, R_SHOULDER, L_ELBOW, R_ELBOW = 11, 12, 13, 14
    L_WRIST, R_WRIST, L_HIP, R_HIP, L_KNEE, R_KNEE, L_ANKLE, R_ANKLE = \
        15, 16, 23, 24, 25, 26, 27, 28

    def ang(a, b, c):
        import math as _m
        bax, bay = a.x - b.x, a.y - b.y
        bcx, bcy = c.x - b.x, c.y - b.y
        den = _m.hypot(bax, bay) * _m.hypot(bcx, bcy)
        if den < 1e-9:
            return 0.0
        cosv = max(-1.0, min(1.0, (bax * bcx + bay * bcy) / den))
        return _m.degrees(_m.acos(cosv))

    def d(a, b):
        import math as _m
        return _m.hypot(a.x - b.x, a.y - b.y)

    def feats(name, lm):
        if name == "Lunge":
            s, h, k, a = lm[L_SHOULDER], lm[L_HIP], lm[L_KNEE], lm[L_ANKLE]
            import math as _m
            return [ang(h, k, a),
                    abs(_m.degrees(_m.atan2(s.x - h.x, -(s.y - h.y)))),
                    abs(_m.degrees(_m.atan2(k.x - a.x, a.y - k.y))),
                    ((a.y - h.y) / d(s, h)) if abs(d(s, h)) > 1e-6 else float("nan"),
                    abs(_m.degrees(_m.atan2(k.x - h.x, k.y - h.y)))]
        if name in ("Plank", "Side Plank"):
            s, h, a, e = lm[L_SHOULDER], lm[L_HIP], lm[L_ANKLE], lm[L_ELBOW]
            back = ang(s, h, a)
            ll = d(s, a)
            if ll < 1e-6:
                hipdev = 0.0
            else:
                num = abs((a.y - s.y) * h.x - (a.x - s.x) * h.y + a.x * s.y - a.y * s.x)
                hipdev = num / ll / ll
            return [back, hipdev, (abs(s.x - e.x) / ll) if ll > 1e-6 else float("nan")]
        if name == "Squat":
            s, h, k, a = lm[L_SHOULDER], lm[L_HIP], lm[L_KNEE], lm[L_ANKLE]
            import math as _m
            return [ang(h, k, a), abs(_m.degrees(_m.atan2(s.x - h.x, -(s.y - h.y))))]
        if name == "Push-Up":
            s, h, a = lm[L_SHOULDER], lm[L_HIP], lm[L_ANKLE]
            return [ang(s, lm[L_ELBOW], lm[L_WRIST]), ang(s, h, a)]
        if name == "Pull-Up":
                    smy = (lm[L_SHOULDER].y + lm[R_SHOULDER].y) / 2
                    hmy = (lm[L_HIP].y + lm[R_HIP].y) / 2
                    le = ang(lm[L_SHOULDER], lm[L_ELBOW], lm[L_WRIST])
                    re = ang(lm[R_SHOULDER], lm[R_ELBOW], lm[R_WRIST])
                    return [hmy - smy, (le + re) / 2.0]
        return None

    need = {
            "Lunge": [L_SHOULDER, L_HIP, L_KNEE, L_ANKLE],
            "Plank": [L_SHOULDER, L_HIP, L_KNEE, L_ANKLE],
            "Side Plank": [L_SHOULDER, L_HIP, L_KNEE, L_ANKLE],
            "Squat": [L_SHOULDER, L_HIP, L_KNEE, L_ANKLE],
            "Push-Up": [L_SHOULDER, L_ELBOW, L_WRIST, L_HIP, L_ANKLE],
            "Pull-Up": [L_SHOULDER, R_SHOULDER, L_ELBOW, R_ELBOW, L_WRIST, R_WRIST],
        }.get(exercise)
    if need is None:
        print(f"       {exercise}: no landmark set defined, keeping held-out radius")
        return None

    dists = []
    for label in ("correct", "incorrect"):
        vdir = DATASET_DIR / exercise / label
        if not vdir.is_dir():
            continue
        vids = sorted(f for f in os.listdir(vdir)
                      if f.lower().endswith((".mov", ".mp4", ".avi")))
        rng.shuffle(vids)
        with mp.solutions.pose.Pose(static_image_mode=False, model_complexity=1,
                                    min_detection_confidence=0.5) as pose:
            for v in vids[:max_videos]:
                cap = cv2.VideoCapture(str(vdir / v))
                idx = 0
                while cap.isOpened():
                    ok, frame = cap.read()
                    if not ok:
                        break
                    idx += 1
                    if idx % sample_every != 0:
                        continue
                    if idx > max_frames:
                        break
                    res = pose.process(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
                    if not res.pose_landmarks:
                        continue
                    lm = res.pose_landmarks.landmark
                    if any(lm[i].visibility < 0.6 for i in need):
                        continue
                    raw = feats(exercise, lm)
                    if raw is None or not all(math.isfinite(x) for x in raw):
                        continue
                    q = zs(raw)
                    dists.append(min(math.sqrt(sum((a - b) ** 2 for a, b in zip(q, zt)))
                                     for zt in ztrain))
                cap.release()

    if not dists:
        print(f"       {exercise}: no reliable live frames found")
        return []
    dists.sort()
    return dists


def load_rows(path=INPUT_CSV):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def example_features(row):
    """Feature vector for one row, using whichever feature_N columns exist."""
    return [float(row[c]) for c in FEATURE_COLS if c in row and row[c] != ""]


def main():
    rows = load_rows()

    # Group rows by exercise.
    by_exercise = {}
    for r in rows:
        by_exercise.setdefault(r["exercise"], []).append(r)

    output = {}
    for exercise, subset in by_exercise.items():
        vectors = [example_features(r) for r in subset]
        dims = len(vectors[0]) if vectors else 0

        # Per-feature mean/std (population std, ddof=0 -- matches sklearn
        # StandardScaler used in train_and_validate.py).
        means = [0.0] * dims
        stds = [0.0] * dims
        n = len(vectors)
        for v in vectors:
            for i in range(dims):
                means[i] += v[i]
        means = [m / n for m in means]
        for v in vectors:
            for i in range(dims):
                stds[i] += (v[i] - means[i]) ** 2
        stds = [(s / n) ** 0.5 for s in stds]
        stds = [sd if sd > 0 else 1.0 for sd in stds]  # avoid divide-by-zero

        output[exercise] = {
            "mean": means,
            "std": stds,
            "examples": [
                {"features": v, "label": r["label"]}
                for v, r in zip(vectors, subset)
            ],
        }

        # Out-of-distribution (OOD) radius, shipped so the app can tell "I
        # don't recognise this pose" from a real Correct/Incorrect verdict.
        #
        # Calibration: hold out ~20% of the examples, measure each held-out
        # pose's distance to its nearest example in the remaining 80%, and take
        # the 99th percentile. That is the smallest radius that keeps ~99% of
        # genuinely valid poses inside, so real correct/incorrect reps are NOT
        # flagged, while poses unlike anything in training fall outside -> app
        # shows "uncertain".
        #
        # Do NOT use the in-model 1-NN distance: consecutive frames of the
        # same rep are near-duplicates, so that distribution is tiny for some
        # exercises (false-flagging good reps) and inflated by duplicates for
        # others (never firing).
        #
        # SMALL-DATA FALLBACK: a percentile is only meaningful when there are
        # enough held-out poses to define one. With a handful (Squat: 29 rows
        # -> 5 held out) "p99" degenerates to the single largest of a few
        # distances -- an arbitrary number. MEASURED on real video, that flags
        # 79.6% of genuine Squat reps as OOD, and a fixed multiple of the
        # in-model 1-NN median (6x) still flags 79.6% / Pull-Up 76.6% /
        # Plank 29.9%, because the in-model median is itself near-zero for
        # these exercises.
        #
        # So for small datasets we calibrate from LIVE VIDEO: replay the
        # training clips through mediapipe, measure each real frame's nearest
        # training-example distance, and take the 99th percentile of THAT. The
        # videos are the ground truth for "what a real rep looks like to the
        # app", and this holds ~1-2% of live frames inside across every
        # exercise (validated end-to-end).
        # So we VALIDATE against live video for EVERY exercise: compute the
        # held-out radius, then replay a few training clips through mediapipe
        # and measure what fraction of real frames fall outside it. If that
        # fraction is too high the held-out radius is untrustworthy (too few
        # samples, or near-duplicate rows making the model distances tiny --
        # which is exactly Plank's failure mode: 454 held-out poses, yet the
        # radius still flags 29.9% of real planks). In that case we replace it
        # with the live-video p99, which holds ~0-2% of real frames inside
        # across every exercise.
        import random
        rng = random.Random(0)
        n = len(vectors)
        zc = [[(v[i] - means[i]) / stds[i] for i in range(dims)] for v in vectors]

        radius = None
        if n >= 10:
            perm = list(range(n))
            rng.shuffle(perm)
            n_hold = max(1, n // 5)
            hold = perm[:n_hold]
            model = perm[n_hold:]
            dists = []
            for h in hold:
                zh = zc[h]
                best = float("inf")
                for b in model:
                    zb = zc[b]
                    d2 = 0.0
                    for i in range(dims):
                        diff = zh[i] - zb[i]
                        d2 += diff * diff
                    if d2 < best:
                        best = d2
                if best < float("inf"):
                    dists.append(math.sqrt(best))
            if dists:
                dists.sort()
                radius = dists[min(len(dists) - 1, int(math.ceil(0.99 * len(dists))) - 1)]

        # Validate whatever we have against real video; fall back to the
        # live-video radius when it lets too many genuine frames escape.
        MAX_OUTSIDE = 0.05
        live = _live_video_dists(exercise, output[exercise])
        if live:
            live.sort()
            lv_p99 = live[min(len(live) - 1, int(math.ceil(0.99 * len(live))) - 1)]
            outside = sum(1 for x in live if x > radius) / len(live) if radius else 1.0
            if radius is None or outside > MAX_OUTSIDE:
                why = "no held-out data" if radius is None else \
                    f"held-out radius {radius:.3f} lets {outside*100:.1f}% of real reps escape"
                print(f"  NOTE {exercise}: {why} -- recalibrating from live video")
                radius = lv_p99
                print(f"       {exercise}: {len(live)} live frames, "
                      f"p50={live[len(live)//2]:.3f} p99={lv_p99:.3f} max={live[-1]:.3f}")
            else:
                print(f"       {exercise}: held-out radius {radius:.3f} holds "
                      f"{(1-outside)*100:.1f}% of {len(live)} real frames -- OK")

        if radius is not None:
            output[exercise]["oodRadius"] = round(max(radius, 1e-3), 4)

    output_path = OUTPUT_JSON
    with open(output_path, "w") as f:
        json.dump(output, f, indent=2)

    print("Wrote knn_training_data.json")
    for exercise, data in output.items():
        dims = len(data["mean"])
        print(f"  {exercise}: {len(data['examples'])} examples, "
              f"{dims} feature(s), mean={[round(m,2) for m in data['mean']]}, "
              f"std={[round(s,2) for s in data['std']]}")

    # Sanity check: warn if feature width varies in a way the Dart side
        # Dart sends: Squat/Push-Up = 2, Pull-Up = 2, Lunge = 5, Plank/Side Plank = 3.
        # Keep this in sync with _classifierFeatures/_lungeFeatures in
        # Expected feature widths, mirroring _classifierFeatures() in
        # lib/pose_analyzer.dart. This is the guard that catches a train/serve
        # feature-width mismatch, which silently destroys accuracy.
        #
        # Pull-Up is 2-D: [vertical_displacement, average_elbow_angle].
        # The elbow angle provides frame-local signal that displacement alone cannot.
        # Keep this in sync with feature_2_value() in extract_features.py and
        # _bonusRatio() in lib/pose_analyzer.dart.
        expected = {"Squat": 2, "Push-Up": 2, "Pull-Up": 2,
                    "Lunge": 5, "Plank": 3, "Side Plank": 3}
        print("\nFeature-width sanity check:")
    for exercise, data in output.items():
        dims = len(data["mean"])
        exp = expected.get(exercise)
        if exp is None:
            print(f"  {exercise}: {dims} features (unexpected exercise name -- check spelling)")
        elif dims != exp:
            print(f"  WARNING {exercise}: exported {dims} features but Dart expects {exp} "
                  f"-- train/serve mismatch! accuracy will be wrong.")
        else:
            print(f"  {exercise}: {dims} features OK")


if __name__ == "__main__":
    main()
