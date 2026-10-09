# -*- coding: utf-8 -*-
"""
Measure the real cost of each algorithm so the paper can justify KNN on
measured grounds rather than assertion. Reports:
  - model size in bytes (what ships on device)
  - mean training time (KNN has none)
  - mean inference latency per single sample (the real-time constraint)
Same features, same exercises as the comparison. Squat excluded.
"""
import json, os, time
import numpy as np
import pandas as pd
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import GroupKFold, GroupShuffleSplit
from sklearn.neighbors import KNeighborsClassifier
from sklearn.svm import SVC
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.tree import DecisionTreeClassifier
from sklearn.naive_bayes import GaussianNB
from sklearn.linear_model import LogisticRegression
import pickle

SEED = 42
EXERCISES = ["Lunge", "Plank", "Side Plank", "Pull-Up", "Push-Up"]
df = pd.read_csv("features.csv")

ALGOS = {
    "KNN (k=5)":        lambda: KNeighborsClassifier(n_neighbors=5),
    "SVM (RBF)":        lambda: SVC(kernel="rbf", random_state=SEED),
    "Random Forest":    lambda: RandomForestClassifier(n_estimators=100, random_state=SEED),
    "Gradient Boosting":lambda: GradientBoostingClassifier(random_state=SEED),
    "Decision Tree":    lambda: DecisionTreeClassifier(random_state=SEED),
    "Naive Bayes":      lambda: GaussianNB(),
    "Logistic Reg.":    lambda: LogisticRegression(max_iter=1000, random_state=SEED),
}

rows = []
for name, factory in ALGOS.items():
    fit_t, inf_t, size = [], [], []
    for ex in EXERCISES:
        sub = df[df.exercise == ex].copy()
        fcols = [c for c in ["feature_1","feature_2","feature_3"] if sub[c].notna().all()]
        X = sub[fcols].values
        y = (sub.label == "correct").astype(int).values
        g = sub.video_id.values
        tr, te = next(GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=SEED)
                      .split(X, y, groups=g))
        sc = StandardScaler().fit(X[tr])
        Xtr, Xte = sc.transform(X[tr]), sc.transform(X[te])
        m = factory()
        t0 = time.perf_counter(); m.fit(Xtr, y[tr]); fit_t.append(time.perf_counter()-t0)
        t0 = time.perf_counter()
        for i in range(len(Xte)):
            m.predict(Xte[i:i+1])
        inf_t.append((time.perf_counter()-t0)/len(Xte))
        size.append(len(pickle.dumps(m)))
    rows.append({
        "algorithm": name,
        "fit_ms":   round(np.mean(fit_t)*1000, 2),
        "infer_ms": round(np.mean(inf_t)*1000, 4),
        "model_kb": round(np.mean(size)/1024, 1),
    })
    print(f"{name:20s} train={np.mean(fit_t)*1000:9.2f} ms  "
          f"infer={np.mean(inf_t)*1000:8.4f} ms/sample  "
          f"model={np.mean(size)/1024:8.1f} KB")

out = pd.DataFrame(rows).sort_values("model_kb")
out.to_csv("algo_cost.csv", index=False)
print("\nsaved algo_cost.csv")
print("\nKNN vs SVM/RF size ratio:",
      round(out[out.algorithm!='KNN (k=5)'].model_kb.mean() / out[out.algorithm=='KNN (k=5)'].model_kb.iloc[0], 1),
      "x larger on average")
