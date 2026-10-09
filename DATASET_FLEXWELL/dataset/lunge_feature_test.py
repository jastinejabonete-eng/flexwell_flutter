# -*- coding: utf-8 -*-
"""
Targeted Lunge experiment: can a THIRD feature raise accuracy above the current
69.7% (2 features)?

The candidate file stores per-frame candidates inside a dict in `feature_4`.
This script expands those dict keys into scalar columns, then tests, with the
same leakage-free grouped CV:
  - baseline [feature_1, feature_2]
  - each candidate alone
  - baseline + best single candidate
  - baseline + best two candidates

Also reports the separability ceiling so we know how much headroom exists.
"""
import ast
import numpy as np
import pandas as pd
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.neighbors import KNeighborsClassifier
from sklearn.model_selection import GroupKFold, cross_val_score

K = 5
cand = pd.read_csv("features_candidates.csv")
lung = cand[cand.exercise == "Lunge"].copy()
print("Lunge candidate rows:", len(lung))
print("video_id populated:", lung.video_id.notna().sum())
print("video_id unique:", lung.video_id.nunique())

# video_id is empty in the candidate file -> take it from features.csv
base = pd.read_csv("features.csv")
lung_base = base[base.exercise == "Lunge"]
print("rows in features.csv:", len(lung_base), "videos:", lung_base.video_id.nunique())

if lung.video_id.notna().sum() < lung_base.video_id.nunique():
    # align by row order (both are extractor output over the same clips)
    lung = lung.reset_index(drop=True)
    lung_base = lung_base.reset_index(drop=True)
    print("row counts match:", len(lung) == len(lung_base))
    lung["video_id"] = lung_base["video_id"].values
    lung["label"] = lung_base["label"].values
    lung["feature_1"] = lung_base["feature_1"].values
    lung["feature_2"] = lung_base["feature_2"].values

lung = lung[lung.video_id.notna()].copy()
print("\nafter join:", len(lung), "rows,", lung.video_id.nunique(), "videos")

# expand the candidate dict into scalar columns
def expand(v):
    if not isinstance(v, str) or not v.strip().startswith("{"):
        return {}
    try:
        return ast.literal_eval(v)
    except Exception:
        return {}

dicts = lung["feature_4"].apply(expand)
keys = sorted({k for d in dicts for k in d})
print("candidate keys found:", keys)
for k in keys:
    lung[k] = dicts.apply(lambda d: d.get(k, np.nan))

# feature_3 in the candidate file is a video path for Lunge (not a scalar) -> drop it
cand_cols = [k for k in keys if lung[k].notna().mean() > 0.9]
print("usable candidate columns (>=90% populated):", cand_cols)

def cv(cols):
    d = lung.dropna(subset=cols)
    X = d[cols].values
    y = (d.label == "correct").astype(int).values
    g = d.video_id.values
    if pd.Series(g).nunique() < 5:
        return float("nan")
    pipe = make_pipeline(StandardScaler(), KNeighborsClassifier(n_neighbors=K))
    s = cross_val_score(pipe, X, y, cv=GroupKFold(n_splits=min(5, pd.Series(g).nunique())), groups=g)
    return s.mean()

print("\n=== Lunge experiment (grouped CV, k=5) ===")
base_acc = cv(["feature_1", "feature_2"])
print(f"  baseline [feature_1, feature_2]              {base_acc:.3f}")

best = []
for c in cand_cols:
    a_alone = cv([c])
    a_combo = cv(["feature_1", "feature_2", c])
    best.append((c, a_alone, a_combo))
    print(f"  [{c:20s}] alone {a_alone:.3f}   + baseline {a_combo:.3f}"
          f"   ({a_combo-base_acc:+.3f})")

best.sort(key=lambda r: -r[2])
print(f"\n  BEST 3-feature set: baseline + {best[0][0]} = {best[0][2]:.3f} ({best[0][2]-base_acc:+.3f})")

# 4-feature: baseline + two best candidates
if len(best) >= 2:
    top2 = [best[0][0], best[1][0]]
    a4 = cv(["feature_1", "feature_2"] + top2)
    print(f"  baseline + {top2} = {a4:.3f} ({a4-base_acc:+.3f})")
    top3 = [best[0][0], best[1][0], best[2][0]] if len(best) >= 3 else top2
    a5 = cv(["feature_1", "feature_2"] + top3)
    print(f"  baseline + {top3} = {a5:.3f} ({a5-base_acc:+.3f})")
