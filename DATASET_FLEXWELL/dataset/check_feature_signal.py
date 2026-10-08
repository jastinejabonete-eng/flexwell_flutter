"""
check_feature_signal.py

The previous diagnostic (diagnose_calibration.py) checked whether
correct/incorrect RANGES overlap -- but with dozens of noisy real-world
videos, full ranges overlapping is almost guaranteed even when a real,
usable difference exists in the middle of the distribution. Overlap is
too blunt a test.

This script instead computes AUC (area under the ROC curve) for each
feature representation against the correct/incorrect label. AUC is a
direct measure of "if I only had this one number, how well could I
separate the two classes":
  - ~0.50 = no discriminative power at all (coin flip)
  - ~0.60-0.70 = weak but real signal
  - ~0.80+ = strong signal, worth building on

It checks several representations per exercise so you can see where (if
anywhere) the signal actually lives:
  - feature_1 / feature_2 at the RAW FRAME level (what the KNN currently
    trains on)
  - per-video MEAN, MIN, MAX of feature_1 (does aggregating over a whole
    rep cycle reveal something frame-level noise hides?)

For Squat, it also reports feature_1 signal with the 4 flagged
scale-blowup videos excluded, to check whether they're dragging down an
otherwise-real signal.

AUC alone can't tell direction (a feature might discriminate "backwards"
depending on your sign convention), so this reports max(auc, 1-auc) --
i.e. "how separable", not "which way".
"""
import pandas as pd
import numpy as np
from sklearn.metrics import roc_auc_score

FRONT_BACK_EXERCISES = {"Squat", "Push-Up", "Pull-Up"}
SCALE_BLOWUP_THRESHOLD = 2.0

df = pd.read_csv("features.csv")


def signal(y_true, score):
    """max(auc, 1-auc): how separable a single score is, direction-agnostic."""
    y_bin = (y_true == "incorrect").astype(int)
    if y_bin.nunique() < 2 or score.nunique() < 2:
        return float("nan")
    auc = roc_auc_score(y_bin, score)
    return max(auc, 1 - auc)


for exercise in FRONT_BACK_EXERCISES:
    subset = df[df["exercise"] == exercise]
    if subset.empty:
        continue

    print(f"\n=== {exercise} ===")
    print(f"  raw frame-level feature_1: AUC={signal(subset['label'], subset['feature_1']):.3f}")
    print(f"  raw frame-level feature_2: AUC={signal(subset['label'], subset['feature_2']):.3f}")

    per_video = subset.groupby(["video_id", "label"]).agg(
        f1_mean=("feature_1", "mean"),
        f1_min=("feature_1", "min"),
        f1_max=("feature_1", "max"),
        f2_mean=("feature_2", "mean"),
    ).reset_index()

    print(f"  per-video MEAN of feature_1: AUC={signal(per_video['label'], per_video['f1_mean']):.3f}")
    print(f"  per-video MIN  of feature_1: AUC={signal(per_video['label'], per_video['f1_min']):.3f}")
    print(f"  per-video MAX  of feature_1: AUC={signal(per_video['label'], per_video['f1_max']):.3f}")
    print(f"  per-video MEAN of feature_2: AUC={signal(per_video['label'], per_video['f2_mean']):.3f}")

    if exercise == "Squat":
        clean = per_video[(per_video["f1_min"].abs() <= SCALE_BLOWUP_THRESHOLD) &
                           (per_video["f1_max"].abs() <= SCALE_BLOWUP_THRESHOLD)]
        print(f"  [excluding {len(per_video) - len(clean)} scale-blowup videos] "
              f"per-video MEAN of feature_1: AUC={signal(clean['label'], clean['f1_mean']):.3f}")

print(
    "\nHow to read this:\n"
    "  - Any AUC noticeably above 0.55-0.60 means that representation has "
    "real, usable signal -- that's the one worth building the next "
    "feature/training scheme around.\n"
    "  - If EVERY representation for an exercise sits at ~0.50, none of "
    "the two current features (as computed) separate correct from "
    "incorrect for it at all -- that calls for new features (different "
    "landmarks/angles), not just a different aggregation or scaler.\n"
)
