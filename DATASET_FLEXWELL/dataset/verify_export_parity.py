"""
verify_export_parity.py

export_for_app.py writes knn_training_data.json with per-exercise
mean/std and a flat list of {features, label} examples, so the Dart app
can reimplement z-score normalization + KNN voting on-device. That
reimplementation is a manual distance calculation, not sklearn -- this
script is the check that the two actually agree before you trust the
on-device numbers to match the validated Python results.

Method, per exercise:
  1. Split videos into train/test with the SAME GroupShuffleSplit scheme
     train_and_validate.py uses (no video's rows in both sides).
  2. Fit sklearn's StandardScaler + KNeighborsClassifier(k=5) on the
     train rows -- this is the "ground truth" pipeline.
  3. Independently build a train-only mean/std + example list, exactly
     the way export_for_app.py builds the full-dataset JSON, then predict
     the test rows with a manual, dependency-free z-score + k=5 majority
     vote (ties broken by alphabetical label, matching sklearn's default
     tie-breaking via np.bincount over sorted classes). This manual
     function is the one to port to Dart.
  4. Compare manual predictions to sklearn predictions row-by-row.

If they match everywhere (or the only mismatches are genuine k=5 ties
resolved the same way), the JSON export + a straightforward on-device
KNN is faithful to what train_and_validate.py already validated. Any
other mismatch means the manual distance calc (and therefore the Dart
port) has a bug -- check normalization order and distance formula first.
"""
import json
import math

import numpy as np
import pandas as pd
from sklearn.model_selection import GroupShuffleSplit
from sklearn.neighbors import KNeighborsClassifier
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

FEATURE_COLS = ["feature_1", "feature_2"]
K = 5

df = pd.read_csv("features.csv")


def manual_knn_predict(train_examples, mean, std, k, query_features):
    """Pure-Python/numpy stand-in for what the Dart app should do:
    z-score the query with the exported mean/std, find the k nearest
    training examples by Euclidean distance, and majority-vote their
    labels (ties broken alphabetically, matching sklearn's default)."""
    q = (np.array(query_features) - mean) / std
    dists = []
    for ex in train_examples:
        f = (np.array(ex["features"]) - mean) / std
        d = math.dist(q, f)
        dists.append((d, ex["label"]))
    dists.sort(key=lambda t: t[0])
    neighbors = dists[:k]
    labels, counts = np.unique([lbl for _, lbl in neighbors], return_counts=True)
    return labels[np.argmax(counts)]  # np.unique sorts labels alphabetically already


for exercise in df["exercise"].unique():
    subset = df[df["exercise"] == exercise]
    X = subset[FEATURE_COLS].values
    y = subset["label"].values
    groups = subset["video_id"].values
    n_videos = subset["video_id"].nunique()

    if len(subset) < 20 or n_videos < 5:
        print(f"\n{exercise}: not enough data/videos for a held-out parity check -- skipped "
              f"(same threshold train_and_validate.py uses).")
        continue

    gss = GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=42)
    train_idx, test_idx = next(gss.split(X, y, groups=groups))
    X_train, X_test = X[train_idx], X[test_idx]
    y_train, y_test = y[train_idx], y[test_idx]

    # --- sklearn ground truth ---
    scaler = StandardScaler().fit(X_train)
    knn = KNeighborsClassifier(n_neighbors=K)
    knn.fit(scaler.transform(X_train), y_train)
    sklearn_preds = knn.predict(scaler.transform(X_test))

    # --- manual export-style prediction (what the Dart app implements) ---
    mean = X_train.mean(axis=0)
    std = X_train.std(axis=0, ddof=0)
    std = np.where(std == 0, 1.0, std)  # same divide-by-zero guard as export_for_app.py
    train_examples = [
        {"features": list(f), "label": lbl} for f, lbl in zip(X_train, y_train)
    ]
    manual_preds = np.array([
        manual_knn_predict(train_examples, mean, std, K, feats) for feats in X_test
    ])

    mismatches = np.sum(sklearn_preds != manual_preds)
    print(f"\n=== {exercise} ({len(X_test)} held-out test rows) ===")
    print(f"  sklearn vs manual export-style KNN: {len(X_test) - mismatches}/{len(X_test)} predictions match")
    if mismatches > 0:
        for i in np.where(sklearn_preds != manual_preds)[0]:
            print(f"    row {i}: sklearn={sklearn_preds[i]!r} manual={manual_preds[i]!r} "
                  f"features={X_test[i].tolist()}")

print(
    "\nHow to read this:\n"
    "  - 100% match for every exercise: the export format + a plain "
    "z-score + k-NN majority vote is enough -- port manual_knn_predict()'s "
    "logic to Dart as-is (z-score with the exported mean/std, Euclidean "
    "distance, majority vote over k=5, alphabetical tie-break) and it will "
    "reproduce these validated numbers on-device.\n"
    "  - Any mismatches: almost always a tie-breaking or distance-formula "
    "difference (e.g. squared vs non-squared Euclidean distance -- doesn't "
    "change ranking so shouldn't matter, but weighting or a different tie "
    "rule would). Print the tied distances for that row before assuming "
    "it's a bug -- genuine k=5 ties are the one case where two 'correct' "
    "implementations can legitimately disagree.\n"
)
