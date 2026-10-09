# -*- coding: utf-8 -*-
"""
Targeted Lunge test using features_candidates.csv, where for Lunge:
  feature_3 = the clip path (80 distinct clips == current video_id count)
  feature_4 = dict of per-frame candidate features
labels (3097 correct / 1947 incorrect) match the current downsampled set.

Tests whether a 3rd/4th candidate feature beats the current 2-feature KNN,
with leakage-free grouped CV by clip.
"""
import ast
import numpy as np
import pandas as pd
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.neighbors import KNeighborsClassifier
from sklearn.model_selection import GroupKFold, cross_val_score

K = 5
c = pd.read_csv("features_candidates.csv")
l = c[c.exercise == "Lunge"].copy()
l["clip"] = l.feature_3.astype(str)
l = l[l["clip"].notna() & (l["clip"] != "nan")]
print("rows:", len(l), "| clips:", l["clip"].nunique(),
      "| labels:", l.label.value_counts().to_dict())

def expand(v):
    if not isinstance(v, str) or not v.strip().startswith("{"):
        return {}
    try:
        return ast.literal_eval(v)
    except Exception:
        return {}

d = l["feature_4"].apply(expand)
keys = sorted({k for x in d for k in x})
for k in keys:
    l[k] = d.apply(lambda x: x.get(k, np.nan))
print("candidate features available:", keys)
for k in keys:
    print(f"   {k:22s} populated {l[k].notna().mean()*100:.1f}%")

def cv(cols):
    dd = l.dropna(subset=cols)
    X = dd[cols].values
    y = (dd.label == "correct").astype(int).values
    g = dd["clip"].values
    nv = pd.Series(g).nunique()
    if nv < 5:
        return float("nan")
    pipe = make_pipeline(StandardScaler(), KNeighborsClassifier(n_neighbors=K))
    s = cross_val_score(pipe, X, y, cv=GroupKFold(n_splits=min(5, nv)), groups=g)
    return s.mean()

BASE = ["feature_1", "feature_2"]
print("\n=== Lunge: grouped-CV accuracy (k=5) ===")
base = cv(BASE)
print(f"  baseline [f1, f2]                       {base:.3f}")

usable = [k for k in keys if l[k].notna().mean() > 0.9]
results = []
for k in usable:
    a3 = cv(BASE + [k])
    results.append((k, a3))
    print(f"  + {k:20s}                  {a3:.3f}  ({a3-base:+.3f})")

results.sort(key=lambda r: -r[1])
if len(results) >= 2:
    a4 = cv(BASE + [results[0][0], results[1][0]])
    print(f"  + {results[0][0]} + {results[1][0]:14s} {a4:.3f}  ({a4-base:+.3f})")
if len(results) >= 3:
    a5 = cv(BASE + [results[0][0], results[1][0], results[2][0]])
    print(f"  + top 3 candidates                      {a5:.3f}  ({a5-base:+.3f})")

if results:
    print(f"\n  BEST: + {results[0][0]} -> {results[0][1]:.3f} ({results[0][1]-base:+.3f})")
