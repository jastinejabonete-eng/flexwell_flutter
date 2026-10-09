# -*- coding: utf-8 -*-
"""
Validate the best Lunge feature set with a proper grouped holdout and a
seed-stability check, so the improvement is trustworthy before adoption.

Best combos from lunge_candidate_test2.py:
  [f1, f2, lg_shin_angle, lg_hip_ankle_gap]  -> CV 0.839
  [f1, f2, lg_shin_angle, lg_hip_ankle_gap, lg_thigh_angle] -> CV 0.849
"""
import ast
import numpy as np
import pandas as pd
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.neighbors import KNeighborsClassifier
from sklearn.model_selection import GroupKFold, GroupShuffleSplit, cross_val_score
from sklearn.metrics import classification_report

c = pd.read_csv("features_candidates.csv")
l = c[c.exercise == "Lunge"].copy()
l["clip"] = l["feature_3"].astype(str)
l = l[l["clip"].notna() & (l["clip"] != "nan")]

d = l["feature_4"].apply(lambda v: ast.literal_eval(v) if isinstance(v, str) and v.strip().startswith("{") else {})
for k in ["lg_shin_angle", "lg_thigh_angle", "lg_rear_knee_angle", "lg_hip_ankle_gap"]:
    l[k] = d.apply(lambda x: x.get(k, np.nan))

y = (l.label == "correct").astype(int).values
g = l["clip"].values

SETS = {
    "current  [f1,f2]":                              ["feature_1", "feature_2"],
    "3-feat   [f1,f2,shin]":                         ["feature_1", "feature_2", "lg_shin_angle"],
    "4-feat   [f1,f2,shin,gap]":                     ["feature_1", "feature_2", "lg_shin_angle", "lg_hip_ankle_gap"],
    "5-feat   [f1,f2,shin,gap,thigh]":               ["feature_1", "feature_2", "lg_shin_angle", "lg_hip_ankle_gap", "lg_thigh_angle"],
}

def ev(cols, seed=42):
    X = l[cols].values
    tr, te = next(GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=seed).split(X, y, groups=g))
    pipe = make_pipeline(StandardScaler(), KNeighborsClassifier(n_neighbors=5))
    pipe.fit(X[tr], y[tr])
    pred = pipe.predict(X[te])
    cv = cross_val_score(pipe, X, y, cv=GroupKFold(n_splits=5), groups=g)
    return (pred == y[te]).mean(), cv.mean(), te

print(f"{'feature set':40s} {'holdout':>8s} {'CV':>7s}")
print("-" * 58)
scores = {}
for name, cols in SETS.items():
    h, cv, _ = ev(cols)
    scores[name] = (h, cv)
    print(f"{name:40s} {h:8.3f} {cv:7.3f}")

# detailed report for the best set
best = max(scores, key=lambda k: scores[k][0])
print(f"\n=== detailed holdout report: {best} ===")
X = l[SETS[best]].values
h, cv, te = ev(SETS[best])
pipe = make_pipeline(StandardScaler(), KNeighborsClassifier(n_neighbors=5))
tr = np.setdiff1d(np.arange(len(y)), te)
pipe.fit(X[tr], y[tr])
print(classification_report(y[te], pipe.predict(X[te]),
                            target_names=["incorrect", "correct"], digits=3))

# seed stability: does the gain survive different splits?
print("=== seed stability (10 splits): accuracy per feature set ===")
seeds = range(10)
tbl = {name: [] for name in SETS}
for s in seeds:
    for name, cols in SETS.items():
        h, _, _ = ev(cols, seed=s)
        tbl[name].append(h)
summary = pd.DataFrame(tbl).agg(["mean", "std", "min"]).round(3)
print(summary.to_string())
cur = np.array(tbl["current  [f1,f2]"]); imp = np.array(tbl["4-feat   [f1,f2,shin,gap]"])
wins = int((imp > cur).sum())
print(f"\n4-feature beats current 2-feature on {wins}/10 random splits")
print(f"mean gain: {(imp-cur).mean():+.3f}")
