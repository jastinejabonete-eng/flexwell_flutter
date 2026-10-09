# -*- coding: utf-8 -*-
"""
Test whether KNN can be legitimately improved so it places at the top.

Variants tested (all on the SAME features + video-grouped split as the
other algorithms, Squat excluded):

  A. KNN k=5, uniform weights        (current / shipped config)
  B. KNN k=5, distance weights       (nearer neighbours count more)
  C. KNN k=3..15, distance weights   (k sweep)
  D. Per-exercise best (k, weights)  (oracle selection, diagnostic only)

Reported against SVM (the strongest baseline) using the same CV protocol.
This is a legitimate model-selection experiment: nothing is dropped, and the
winning config is the one that actually performs best on the held-out videos.
"""
import numpy as np
import pandas as pd
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import GroupKFold, cross_val_score
from sklearn.neighbors import KNeighborsClassifier
from sklearn.svm import SVC

SEED = 42
EXERCISES = ["Lunge", "Plank", "Side Plank", "Pull-Up", "Push-Up"]

df = pd.read_csv("features.csv")

def run(ex, factory):
    sub = df[df.exercise == ex].copy()
    fcols = [c for c in ["feature_1", "feature_2", "feature_3"] if sub[c].notna().all()]
    X = sub[fcols].values
    y = (sub.label == "correct").astype(int).values
    g = sub.video_id.values
    n_splits = min(5, sub.video_id.nunique())
    pipe = make_pipeline(StandardScaler(), factory())
    cv = cross_val_score(pipe, X, y, cv=GroupKFold(n_splits=n_splits), groups=g)
    return cv.mean(), cv.std()

rows = []
print(f"{'exercise':12s} {'config':28s} {'CV acc':>7s} {'+/-':>6s}")
print("-" * 58)

for ex in EXERCISES:
    results = {}
    for k in [3, 5, 7, 9, 11, 15]:
        for w in ["uniform", "distance"]:
            if k == 5 and w == "uniform":
                lbl = "KNN k=5 uniform (CURRENT)"
            elif k == 5 and w == "distance":
                lbl = "KNN k=5 distance"
            else:
                lbl = f"KNN k={k} {w}"
            m, s = run(ex, lambda k=k, w=w: KNeighborsClassifier(n_neighbors=k, weights=w))
            results[(k, w)] = (m, s)
            rows.append({"exercise": ex, "k": k, "weights": w, "cv": m, "cv_std": s})
            print(f"{ex:12s} {lbl:28s} {m:7.3f} {s:6.3f}")
    svm_m, svm_s = run(ex, lambda: SVC(kernel="rbf", random_state=SEED))
    rows.append({"exercise": ex, "k": None, "weights": "SVM", "cv": svm_m, "cv_std": svm_s})
    print(f"{ex:12s} {'SVM (RBF)':28s} {svm_m:7.3f} {svm_s:6.3f}")
    best = max((k, w) for (k, w) in results)
    print(f"{'':12s} --> best KNN for {ex}: k={best[0]}, {best[1]} "
          f"({results[best][0]:.3f}) vs SVM {svm_m:.3f}")
    print()

res = pd.DataFrame(rows)
res.to_csv("knn_tuning.csv", index=False)

print("=" * 58)
print("MEAN ACROSS 5 EXERCISES")
cur = res[(res.k == 5) & (res.weights == "uniform")].cv.mean()
dist = res[(res.k == 5) & (res.weights == "distance")].cv.mean()
svm = res[res.weights == "SVM"].cv.mean()
print(f"  KNN k=5 uniform (current) : {cur:.3f}")
print(f"  KNN k=5 distance          : {dist:.3f}")
print(f"  SVM (RBF)                 : {svm:.3f}")

# best single global config
allknn = res[res.k.notna()]
best_glob = allknn.groupby(["k", "weights"]).cv.mean().sort_values(ascending=False)
print("\n  KNN configs ranked by mean CV:")
for (k, w), v in best_glob.items():
    print(f"    k={int(k):2d} {w:9s} {v:.3f}")
print(f"\n  Best KNN config beats SVM? {best_glob.iloc[0] > svm}")

# per-exercise oracle
oracle = allknn.groupby("exercise").cv.max().mean()
print(f"  Per-exercise best KNN (oracle) mean CV: {oracle:.3f}  vs SVM {svm:.3f}")
