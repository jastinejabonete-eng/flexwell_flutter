"""
audit_label_mixing.py

Quantifies frame-label mixing per exercise/video in features.csv.

Background (2026-11-06 session): probes at the exact good-cluster means of
Plank / Side Plank / Lunge still vote 'incorrect' among their own k=5 nearest
neighbours, even though the same data validates at 78-85% accuracy under
video-grouped CV. Hypothesis: labels are VIDEO-level (from folder names), but
frames inside a video labelled 'incorrect' (or 'correct') include spans whose
features sit deep inside the OTHER label's cluster. Per-frame inference in the
app (used verbatim for hold exercises) inherits that noise.

Method (leave-one-video-out, so no video judges its own frames):
  1. For each video, take its row-level feature matrix.
  2. k=5 z-space vote over the rows of every OTHER video.
  3. Report per-video: agreement of the frame votes with the video label,
     plus the vote on the video's mean feature vector.

Usage:
  python audit_label_mixing.py [exercise ...]
"""
import json
import math
import os
import sys

import numpy as np
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
CSV = os.path.join(HERE, "features.csv")
K = 5


def frame_votes(X, y, target_X, k=K):
    """kNN vote for each row of target_X using the pool X (z-space)."""
    mean = np.asarray(X, dtype=float).mean(axis=0)
    std = np.asarray(X, dtype=float).std(axis=0)
    std[std == 0] = 1e-9
    Z = (X - mean) / std
    Zt = (np.asarray(target_X, dtype=float) - mean) / std
    out = []
    for row in Zt:
        d = np.sqrt(((Z - row) ** 2).sum(axis=1))
        idx = np.argsort(d)[:k]
        out.append(int(sum(y[i] != "correct" for i in idx)))
    return np.array(out)


def main():
    df = pd.read_csv(CSV)
    targets = sys.argv[1:] or sorted(df["exercise"].unique())
    for exercise in targets:
        sub = df[df["exercise"] == exercise].copy()
        cols = [c for c in [f"feature_{i}" for i in range(1, 6)]
                if c in sub.columns and sub[c].notna().all()]
        print(f"\n=== {exercise}: {len(sub)} rows, {sub['video_id'].nunique()} videos, "
              f"{len(cols)} features ===")
        worst = []
        for vid, g in sub.groupby("video_id"):
            pool_X = sub.loc[~sub["video_id"].isin([vid]), cols]
            pool_y = sub.loc[~sub["video_id"].isin([vid]), "label"].to_numpy()
            votes = frame_votes(pool_X, pool_y, g[cols])
            # cleaner: majority vote per frame
            frac_disagree = float(np.mean((votes > K // 2) != (g["label"] != "correct").to_numpy()))
            # vote on the video centroid
            centroid = g[cols].mean(axis=0).to_frame().T
            cv = int(frame_votes(pool_X, pool_y, centroid)[0]) > K // 2
            video_is_incorrect = g["label"].iloc[0] != "correct"
            centroid_disagrees = cv != video_is_incorrect
            worst.append((vid, len(g), float(frac_disagree), centroid_disagrees,
                          g["label"].iloc[0]))
        dfw = pd.DataFrame(worst, columns=["video", "rows", "frame_disagree",
                                           "centroid_disagrees", "label"])
        dfw = dfw.sort_values("frame_disagree", ascending=False)
        print(f"videos with >50% frames voting against their label: "
              f"{int((dfw.frame_disagree > 0.5).sum())}/{len(dfw)}")
        print(dfw.head(12).to_string(index=False))
        print(f"mean frame disagreement overall: {dfw.frame_disagree.mean():.2%}")


if __name__ == "__main__":
    main()
