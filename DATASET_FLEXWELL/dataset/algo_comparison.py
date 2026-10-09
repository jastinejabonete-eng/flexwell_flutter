# -*- coding: utf-8 -*-
"""
Algorithm comparison for FlexWell: KNN vs. 6 other classifiers, on the SAME
features, SAME video-grouped split, SAME protocol as train_and_validate.py.

IMPORTANT FIX vs train_and_validate.py: uses ALL feature columns that are
populated for each exercise (Plank/Side Plank have 3), not a hardcoded
["feature_1","feature_2"].

Squat is EXCLUDED (user is collecting more data; 28 rows is not comparable).

Outputs:
  - algo_comparison.csv          (raw numbers per exercise x algorithm)
  - algo_comparison_summary.json (aggregates)
"""
import json
import numpy as np
import pandas as pd
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import GroupKFold, cross_val_score
from sklearn.model_selection import GroupShuffleSplit
from sklearn.metrics import precision_recall_fscore_support, accuracy_score
from sklearn.neighbors import KNeighborsClassifier
from sklearn.svm import SVC
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.tree import DecisionTreeClassifier
from sklearn.naive_bayes import GaussianNB
from sklearn.linear_model import LogisticRegression

SEED = 42
ALGOS = {
    "KNN (k=5)":        lambda: KNeighborsClassifier(n_neighbors=5),
    "SVM (RBF)":        lambda: SVC(kernel="rbf", random_state=SEED),
    "Random Forest":    lambda: RandomForestClassifier(n_estimators=100, random_state=SEED),
    "Decision Tree":    lambda: DecisionTreeClassifier(random_state=SEED),
    "Gradient Boosting":lambda: GradientBoostingClassifier(random_state=SEED),
    "Naive Bayes":      lambda: GaussianNB(),
    "Logistic Reg.":    lambda: LogisticRegression(max_iter=1000, random_state=SEED),
}

# Tree/boosting models don't need scaling; adding a scaler is harmless but
# keep every algorithm under an identical pipeline for a fair comparison.
df = pd.read_csv("features.csv")
EXERCISES = ["Lunge", "Plank", "Side Plank", "Pull-Up", "Push-Up"]  # Squat excluded

rows = []
for ex in EXERCISES:
    sub = df[df.exercise == ex].copy()
    n_videos = sub.video_id.nunique()
    if len(sub) < 20 or n_videos < 5:
        print(f"{ex}: skipped (n={len(sub)}, videos={n_videos})")
        continue

    # FIX: use every populated feature column for this exercise
    fcols = [c for c in ["feature_1", "feature_2", "feature_3"] if sub[c].notna().all()]
    X = sub[fcols].values
    y = (sub.label == "correct").astype(int).values
    g = sub.video_id.values
    n_splits = min(5, n_videos)
    print(f"\n=== {ex} ({len(sub)} rows, {n_videos} videos, features={fcols}) ===")

    for name, factory in ALGOS.items():
        # 1) grouped CV accuracy (no clip leakage)
        pipe = make_pipeline(StandardScaler(), factory())
        cv = cross_val_score(pipe, X, y, cv=GroupKFold(n_splits=n_splits), groups=g)

        # 2) grouped holdout for precision/recall/F1 (macro)
        gss = GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=SEED)
        tr, te = next(gss.split(X, y, groups=g))
        pipe2 = make_pipeline(StandardScaler(), factory())
        pipe2.fit(X[tr], y[tr])
        pred = pipe2.predict(X[te])
        prec, rec, f1, _ = precision_recall_fscore_support(
            y[te], pred, average="macro", zero_division=0)
        acc = accuracy_score(y[te], pred)

        rows.append({
            "exercise": ex,
            "algorithm": name,
            "n_rows": int(len(sub)),
            "n_videos": int(n_videos),
            "n_features": len(fcols),
            "cv_accuracy": round(float(cv.mean()), 4),
            "cv_std": round(float(cv.std()), 4),
            "holdout_accuracy": round(float(acc), 4),
            "precision": round(float(prec), 4),
            "recall": round(float(rec), 4),
            "f1": round(float(f1), 4),
        })
        print(f"  {name:20s} CV={cv.mean():.3f} (+/-{cv.std():.3f})  "
              f"holdout_acc={acc:.3f}  P={prec:.3f} R={rec:.3f} F1={f1:.3f}")

out = pd.DataFrame(rows)
out.to_csv("algo_comparison.csv", index=False)

summary = {
    "exercises": EXERCISES,
    "algorithms": list(ALGOS.keys()),
    "note": "Squat excluded (insufficient data). Grouped by video_id.",
    "mean_cv_accuracy_by_algorithm": out.groupby("algorithm").cv_accuracy.mean().round(3).to_dict(),
    "mean_f1_by_algorithm": out.groupby("algorithm").f1.mean().round(3).to_dict(),
    "best_per_exercise": {ex: out[out.exercise == ex].sort_values(
        "cv_accuracy", ascending=False).iloc[0].algorithm for ex in EXERCISES},
}
with open("algo_comparison_summary.json", "w") as f:
    json.dump(summary, f, indent=2)

print("\n=== SAVED ===")
print("algo_comparison.csv, algo_comparison_summary.json")
print("\nMean CV accuracy by algorithm:")
for k, v in sorted(summary["mean_cv_accuracy_by_algorithm"].items(), key=lambda x: -x[1]):
    print(f"  {k:20s} {v}")
print("\nBest per exercise:", summary["best_per_exercise"])
