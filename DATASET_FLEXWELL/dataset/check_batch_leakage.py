"""
check_batch_leakage.py

Tests whether Squat's poor holdout accuracy is concentrated in one of the
two video sources (the "IMG_31xx" filming session vs. the per-subject
"subject_0XX_squat_*" clips), which would point to a session-level shortcut
rather than a genuinely weak feature.

Run this against your existing features.csv -- it does NOT require
re-running extract_features.py first. It re-does a grouped 5-fold CV (same
idea as train_and_validate.py) but reports accuracy separately per batch
instead of one pooled number.

Usage:
    python check_batch_leakage.py features.csv
"""
import argparse
import pandas as pd
from pathlib import PureWindowsPath
from sklearn.model_selection import GroupKFold
from sklearn.neighbors import KNeighborsClassifier
from sklearn.preprocessing import StandardScaler


def batch_of(video_id: str) -> str:
    fname = PureWindowsPath(str(video_id).replace("/", "\\")).name
    return "IMG" if fname.upper().startswith(("IMG", "COPY")) else "subject"


def evaluate(exercise: str, df: pd.DataFrame, k: int = 5, n_splits: int = 5):
    g = df[df.exercise == exercise].copy()
    if g.empty:
        print(f"\n=== {exercise}: no rows found ===")
        return
    g["batch"] = g.video_id.map(batch_of)
    y_all = (g.label == "incorrect").to_numpy().astype(int)
    groups = g.video_id.to_numpy()
    batches = g.batch.to_numpy()

    feature_sets = {
        "feature_1+feature_2": ["feature_1", "feature_2"],
        "feature_1 only": ["feature_1"],
        "feature_2 only": ["feature_2"],
    }

    print(f"\n=== {exercise}: accuracy by batch, pooled across grouped CV ===")
    for label, cols in feature_sets.items():
        X = g[cols].to_numpy()
        per_batch_correct = {"IMG": 0, "subject": 0}
        per_batch_total = {"IMG": 0, "subject": 0}

        n_groups = g.video_id.nunique()
        if n_groups < 2:
            raise ValueError(f"{exercise}: grouped CV needs at least 2 distinct videos")
        actual_splits = min(n_splits, n_groups)
        gkf = GroupKFold(n_splits=actual_splits)
        for train_idx, test_idx in gkf.split(X, y_all, groups):
            scaler = StandardScaler().fit(X[train_idx])
            clf = KNeighborsClassifier(n_neighbors=min(k, len(train_idx)))
            clf.fit(scaler.transform(X[train_idx]), y_all[train_idx])
            preds = clf.predict(scaler.transform(X[test_idx]))
            correct = preds == y_all[test_idx]
            for b in ("IMG", "subject"):
                mask = batches[test_idx] == b
                per_batch_correct[b] += correct[mask].sum()
                per_batch_total[b] += mask.sum()

        print(f"  [{label}]")
        for b in ("IMG", "subject"):
            total = per_batch_total[b]
            if total == 0:
                continue
            acc = per_batch_correct[b] / total
            print(f"    {b:8s}: {acc:.2f} accuracy  ({per_batch_correct[b]}/{total})")

    print("  Row counts and majority-class ('always correct') baseline:")
    counts = g.groupby(["batch", "label"]).size().unstack(fill_value=0)
    counts["majority_baseline"] = (counts["correct"] / counts.sum(axis=1)).round(3)
    print(counts.to_string())


def main():
    parser = argparse.ArgumentParser(description="Compare grouped-CV accuracy across video source batches.")
    parser.add_argument("csv", nargs="?", default="features.csv", help="feature CSV (default: features.csv)")
    args = parser.parse_args()
    df = pd.read_csv(args.csv)
    required = {"exercise", "label", "feature_1", "feature_2", "video_id"}
    missing = sorted(required - set(df.columns))
    if missing:
        raise ValueError(f"{args.csv} is missing required columns: {', '.join(missing)}")
    if df.empty:
        raise ValueError(f"{args.csv} has no data rows")

    found = False
    for exercise in ["Squat", "Push-Up", "Lunge", "Plank", "Pull-Up", "Side Plank"]:
        if exercise in df.exercise.unique():
            evaluate(exercise, df)
            found = True
    if not found:
        print("No Squat or Push-Up rows found in the input CSV.")


if __name__ == "__main__":
    main()
