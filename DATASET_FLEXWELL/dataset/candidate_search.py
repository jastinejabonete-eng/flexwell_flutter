"""
candidate_search.py
Automatically searches feature combinations per exercise to find one that
beats the current two-feature KNN, using the SAME grouped-by-video
cross-validation the paper reports (so the comparison is honest and
leakage-free).

Run from inside the DATASET_FLEXWELL/dataset/ folder:
    python candidate_search.py

It reads features_candidates.csv (same rows as features.csv, plus the
experimental candidate columns) and, for each exercise:
  1. warns when the holdout test set is too small to trust,
  2. compares the current [feature_1, feature_2] against
       - each candidate column alone,
       - the best single candidate + each original feature,
       - the best 3-feature combo (greedy forward selection),
  3. prints the ranked winner so you can decide what to add to the
     feature vector, the Dart extractors, and the JSON export.

Nothing here changes training permanently -- it only prints. You decide
whether to adopt a winner.
"""
import itertools
import sys

import numpy as np
import pandas as pd
from sklearn.model_selection import GroupKFold, GroupShuffleSplit, cross_val_score
from sklearn.neighbors import KNeighborsClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import make_pipeline

CSV = "features_candidates.csv"
BASE_FEATURES = ["feature_1", "feature_2"]
K = 5

# Minimum holdout test reps for the holdout accuracy to mean anything.
MIN_HOLDOUT_SUPPORT = 30


def grouped_cv_accuracy(X, y, groups, k=K):
    """Leakage-free grouped CV accuracy. Returns NaN if too few videos."""
    n_videos = pd.Series(groups).nunique()
    if n_videos < 5:
        return float("nan")
    n_splits = min(5, n_videos)
    pipe = make_pipeline(StandardScaler(), KNeighborsClassifier(n_neighbors=k))
    scores = cross_val_score(pipe, X, y, cv=GroupKFold(n_splits=n_splits), groups=groups)
    return scores.mean()


def holdout_report(df, cols, k=K):
    """Grouped holdout: returns (accuracy, incorrect_recall, n_test) or None."""
    if "video_id" not in df.columns or df["video_id"].nunique() < 5:
        return None
    X = df[cols].values
    y = df["label"].values
    groups = df["video_id"].values
    gss = GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=42)
    train_idx, test_idx = next(gss.split(X, y, groups=groups))
    pipe = make_pipeline(StandardScaler(), KNeighborsClassifier(n_neighbors=k))
    pipe.fit(X[train_idx], y[train_idx])
    pred = pipe.predict(X[test_idx])
    acc = (pred == y[test_idx]).mean()
    # recall specifically for the "incorrect" class (catching bad form)
    inc_mask = y[test_idx] == "incorrect"
    inc_recall = (pred[inc_mask] == "incorrect").mean() if inc_mask.any() else float("nan")
    return acc, inc_recall, int(len(test_idx))


def main():
    try:
        df_all = pd.read_csv(CSV)
    except FileNotFoundError:
        sys.exit(f"Run this from the dataset/ folder; {CSV} not found here.")

    candidate_cols = [c for c in df_all.columns
                      if c not in BASE_FEATURES
                      and c not in ("exercise", "label", "video_id")]

    for exercise in sorted(df_all["exercise"].unique()):
        df = df_all[df_all["exercise"] == exercise].dropna(subset=BASE_FEATURES).copy()
        n = len(df)
        n_videos = df["video_id"].nunique() if "video_id" in df else 0
        print(f"\n{'='*66}\n{exercise}: {n} samples from {n_videos} videos\n{'='*66}")

        # candidate columns that actually have data for this exercise
        usable = [c for c in candidate_cols if df[c].notna().sum() > 0.5 * n]
        if not usable:
            print("  (no usable candidate columns for this exercise)")
            continue

        # ---- baseline ----
        base_acc = grouped_cv_accuracy(df[BASE_FEATURES].values, df["label"].values, df["video_id"].values)
        print(f"  baseline [feature_1, feature_2]      CV acc = {base_acc:.3f}")
        ho = holdout_report(df, BASE_FEATURES)
        if ho:
            acc, inc_rec, ntest = ho
            flag = "  <-- TOO SMALL to trust" if ntest < MIN_HOLDOUT_SUPPORT else ""
            print(f"    holdout: acc={acc:.2f}  incorrect-recall={inc_rec:.2f}  n_test={ntest}{flag}")

        results = []  # (cv_acc, description)

        # ---- each candidate column ALONE ----
        print("  single candidate columns (CV acc):")
        for c in usable:
            a = grouped_cv_accuracy(df[[c]].values, df["label"].values, df["video_id"].values)
            marker = " *beats baseline*" if a > base_acc else ""
            print(f"    {c:24s} {a:.3f}{marker}")
            results.append((a, f"[{c}]"))

        # ---- best single candidate + each original feature (3 candidates max shown) ----
        usable_sorted = sorted(usable, key=lambda c: -grouped_cv_accuracy(
            df[[c]].values, df["label"].values, df["video_id"].values))
        top_singles = usable_sorted[:3]
        print("  top candidate + each base feature:")
        for c in top_singles:
            for bf in BASE_FEATURES:
                cols = [bf, c]
                if len(set(cols)) < 2:
                    continue
                a = grouped_cv_accuracy(df[cols].values, df["label"].values, df["video_id"].values)
                marker = " *beats baseline*" if a > base_acc else ""
                print(f"    [{bf} + {c:20s}] {a:.3f}{marker}")
                results.append((a, f"[{bf}, {c}]"))

        # ---- greedy forward selection for a 3-feature combo ----
        pool = usable + BASE_FEATURES
        chosen = list(BASE_FEATURES)
        best_so_far = base_acc
        for _ in range(1):  # add exactly one more feature -> 3 total
            trial_best = None
            for c in pool:
                if c in chosen:
                    continue
                cols = chosen + [c]
                a = grouped_cv_accuracy(df[cols].values, df["label"].values, df["video_id"].values)
                if trial_best is None or a > trial_best[0]:
                    trial_best = (a, c, cols)
            if trial_best and trial_best[0] > best_so_far:
                best_so_far, added, cols = trial_best
                chosen = cols
                print(f"  greedy 3-feature: +{added} -> {best_so_far:.3f}  {cols}")
                results.append((best_so_far, str(cols)))

        # ---- ranked winner ----
        results.sort(reverse=True)
        winner_acc, winner_desc = results[0]
        print(f"\n  >>> BEST for {exercise}: {winner_desc}  CV acc = {winner_acc:.3f}")
        if winner_acc <= base_acc:
            print(f"      (baseline already optimal -- current features are fine here)")
        else:
            delta = winner_acc - base_acc
            print(f"      (+{delta:.3f} over baseline -- candidate for adoption)")


if __name__ == "__main__":
    main()
