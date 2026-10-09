# -*- coding: utf-8 -*-
"""
A/B test: does capping the 11 slow-motion Lunge clips (240fps, ~200-256 rows each)
to 50 rows change Lunge accuracy for the better?
Runs grouped-CV (by video_id) + 80/20 video-grouped holdout on BOTH datasets.
"""
import pandas as pd, numpy as np
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.neighbors import KNeighborsClassifier
from sklearn.model_selection import GroupKFold, cross_val_score, GroupShuffleSplit
from sklearn.metrics import classification_report

CAP = 50
SLOWMO = [f"IMG_26{n:02d}" for n in range(49, 60)]  # IMG_2649..IMG_2659

def stride_indices(n, cap):
    if n <= cap: return list(range(n))
    step = (n - 1) / (cap - 1)
    return sorted({round(i * step) for i in range(cap)})

def evaluate(df, label):
    """Per-exercise grouped-CV accuracy + overall."""
    df = df[df.video_id.notna()].copy()
    feature_cols = [c for c in ["feature_1","feature_2","feature_3"] if c in df.columns]
    print(f"\n########## {label} ({len(df)} rows) ##########")
    accs = {}
    for ex in ["Lunge","Plank","Side Plank","Pull-Up","Push-Up","Squat"]:
        sub = df[df.exercise == ex]
        nvid = sub.video_id.nunique()
        if nvid < 2:
            print(f"  {ex:11s}: only {nvid} video(s) -- skipped"); continue
        X = sub[feature_cols].fillna(0).values
        y = (sub.label == "correct").astype(int).values
        g = sub.video_id.values
        nsplit = min(5, nvid)
        pipe = Pipeline([("sc", StandardScaler()),
                         ("knn", KNeighborsClassifier(n_neighbors=5))])
        scores = cross_val_score(pipe, X, y, cv=GroupKFold(n_splits=nsplit), groups=g)
        accs[ex] = scores.mean()
        print(f"  {ex:11s}: CV acc = {scores.mean():.2f} (+/- {scores.std():.2f}) "
              f"[{nsplit}-fold, {nvid} videos, {len(sub)} rows]")
    if accs:
        print(f"  --> mean CV acc across exercises: {np.mean(list(accs.values())):.3f}")
    return accs

# ---- load current data ----
df_full = pd.read_csv("features.csv")
acc_before = evaluate(df_full, "BEFORE (current, slow-mo clips full length)")

# ---- build downsampled version ----
mask_drop = pd.Series(False, index=df_full.index)
for vid in df_full.video_id.dropna().unique():
    if any(s in str(vid) for s in SLOWMO):
        idx = df_full.index[df_full.video_id == vid]
        keep = stride_indices(len(idx), CAP)
        drop = [i for i in idx if i not in [idx[j] for j in keep]]
        mask_drop.loc[drop] = True
df_cap = df_full[~mask_drop].copy()
n_removed = int(mask_drop.sum())
print(f"\n(downsample removes {n_removed} rows from {len(SLOWMO)} slow-mo clips)")
acc_after = evaluate(df_cap, "AFTER (slow-mo clips capped to 50 rows)")

# ---- verdict ----
print("\n================ VERDICT ================")
for ex in acc_before:
    if ex in acc_after:
        b, a = acc_before[ex], acc_after[ex]
        arrow = "BETTER" if a > b else ("WORSE" if a < b else "same")
        print(f"  {ex:11s}: {b:.2f} -> {a:.2f}  ({arrow}, {a-b:+.2f})")
