# -*- coding: utf-8 -*-
"""
Is k=15 KNN genuinely better than SVM, or is 0.796 vs 0.793 noise?
Reports the per-exercise paired comparison and McNemar-style exact test on
the holdout predictions, plus a seed-stability check.
"""
import numpy as np
import pandas as pd
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import GroupKFold, GroupShuffleSplit, cross_val_predict
from sklearn.neighbors import KNeighborsClassifier
from sklearn.svm import SVC
from scipy.stats import binomtest, wilcoxon

SEED = 42
EXERCISES = ["Lunge", "Plank", "Side Plank", "Pull-Up", "Push-Up"]
df = pd.read_csv("features.csv")

def load(ex):
    sub = df[df.exercise == ex].copy()
    fcols = [c for c in ["feature_1", "feature_2", "feature_3"] if sub[c].notna().all()]
    return sub[fcols].values, (sub.label == "correct").astype(int).values, sub.video_id.values

print(f"{'exercise':12s} {'k=5':>6s} {'k=15':>6s} {'SVM':>6s} {'k=15-SVM':>9s} {'p':>7s}")
print("-" * 52)
pairs = []
for ex in EXERCISES:
    X, y, g = load(ex)
    n_splits = min(5, len(set(g)))
    cv = GroupKFold(n_splits=n_splits)

    p5 = make_pipeline(StandardScaler(), KNeighborsClassifier(n_neighbors=5))
    p15 = make_pipeline(StandardScaler(), KNeighborsClassifier(n_neighbors=15))
    psvm = make_pipeline(StandardScaler(), SVC(kernel="rbf", random_state=SEED))

    a5 = cross_val_predict(p5, X, y, cv=cv, groups=g)   # NOTE: grouped CV predictions
    a15 = cross_val_predict(p15, X, y, cv=cv, groups=g)
    asvm = cross_val_predict(psvm, X, y, cv=cv, groups=g)

    acc = lambda a: (a == y).mean()
    # McNemar (paired, same folds) on k=15 vs SVM
    b = int(((a15 == y) & (asvm != y)).sum())   # k15 right, svm wrong
    c = int(((a15 != y) & (asvm == y)).sum())   # svm right, k15 wrong
    p = binomtest(min(b, c), b + c, 0.5).pvalue if b + c > 0 else 1.0
    pairs.append((ex, acc(a5), acc(a15), acc(asvm)))
    print(f"{ex:12s} {acc(a5):6.3f} {acc(a15):6.3f} {acc(asvm):6.3f} "
          f"{acc(a15)-acc(asvm):+9.3f} {p:7.3f}")

d = pd.DataFrame(pairs, columns=["exercise", "k5", "k15", "svm"])
print("-" * 52)
print(f"{'MEAN':12s} {d.k5.mean():6.3f} {d.k15.mean():6.3f} {d.svm.mean():6.3f} "
      f"{d.k15.mean()-d.svm.mean():+9.3f}")

# paired across exercises (n=5) - is k15 better than SVM per exercise?
try:
    w = wilcoxon(d.k15.values, d.svm.values)
    print(f"\nPaired Wilcoxon (per-exercise, n=5): p = {w.pvalue:.3f}")
except Exception as e:
    print("\nWilcoxon:", e)

wins = int((d.k15 > d.svm).sum())
print(f"k=15 beats SVM on {wins}/5 exercises")

# seed stability: how often does the ranking flip?
print("\n=== seed stability (10 random seeds, k=15 vs SVM) ===")
rng = np.random.default_rng(0)
flips = 0
for s in range(10):
    tot15 = totsvm = 0
    for ex in EXERCISES:
        X, y, g = load(ex)
        gss = GroupShuffleSplit(n_splits=1, test_size=0.2, random_state=s)
        tr, te = next(gss.split(X, y, groups=g))
        for name, tot in (("k15", None),):
            pass
        m15 = make_pipeline(StandardScaler(), KNeighborsClassifier(n_neighbors=15)).fit(X[tr], y[tr])
        msvm = make_pipeline(StandardScaler(), SVC(kernel="rbf", random_state=s)).fit(X[tr], y[tr])
        tot15 += (m15.predict(X[te]) == y[te]).sum()
        totsvm += (msvm.predict(X[te]) == y[te]).sum()
    tag = "k15 wins" if tot15 > totsvm else "SVM wins"
    if tot15 <= totsvm:
        flips += 1
    print(f"  seed {s}: k15 correct={tot15:4d}  SVM correct={totsvm:4d}   -> {tag}")
print(f"\nSVM wins or ties in {flips}/10 random splits.")
