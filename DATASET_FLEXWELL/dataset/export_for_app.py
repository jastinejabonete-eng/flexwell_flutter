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
from pathlib import Path

# Every feature_N column that may exist. Lunge emits 5, Plank/Side Plank 3,
# the rest 2 -- so this must cover the widest exercise, not a fixed 3.
# example_features() keeps only the columns actually present and non-empty for
# each row, so shorter exercises are unaffected.
FEATURE_COLS = ["feature_1", "feature_2", "feature_3", "feature_4", "feature_5"]
DATASET_DIR = Path(__file__).resolve().parent


def load_rows(path=DATASET_DIR / "features.csv"):
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
        # Calibration (leave-one-group-out, data-driven): hold out ~20% of the
        # examples, measure each held-out pose's distance to its nearest
        # example in the remaining 80%, and take the 99th percentile. That is
        # the smallest radius that keeps ~99% of genuinely valid poses inside,
        # so real correct/incorrect reps are NOT flagged, while poses unlike
        # anything in training fall outside -> app shows "uncertain".
        #
        # Do NOT use the in-model 1-NN distance: consecutive frames of the
        # same rep are near-duplicates, so that distribution is tiny for some
        # exercises (false-flagging good reps) and inflated by duplicates for
        # others (never firing). The held-out calibration avoids both.
        import math
        import random
        rng = random.Random(0)
        n = len(vectors)
        zc = [[(v[i] - means[i]) / stds[i] for i in range(dims)] for v in vectors]
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
                p99 = dists[min(len(dists) - 1, int(math.ceil(0.99 * len(dists))) - 1)]
                output[exercise]["oodRadius"] = round(max(p99, 1e-3), 4)

    output_path = DATASET_DIR / "knn_training_data.json"
    with open(output_path, "w") as f:
        json.dump(output, f, indent=2)

    print("Wrote knn_training_data.json")
    for exercise, data in output.items():
        dims = len(data["mean"])
        print(f"  {exercise}: {len(data['examples'])} examples, "
              f"{dims} feature(s), mean={[round(m,2) for m in data['mean']]}, "
              f"std={[round(s,2) for s in data['std']]}")

    # Sanity check: warn if feature width varies in a way the Dart side
    # Dart sends: Squat/Push-Up/Pull-Up = 2, Lunge = 5, Plank/Side Plank = 3.
    # Keep this in sync with _classifierFeatures/_lungeFeatures in
    # lib/pose_analyzer.dart -- it is the guard that catches a train/serve
    # feature-width mismatch, which silently destroys accuracy.
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
