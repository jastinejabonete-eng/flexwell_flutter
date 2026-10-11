# -*- coding: utf-8 -*-
"""
feature_study.py -- which candidate features actually improve each exercise?

Run this after re-extracting features (extract_features.py) whenever you've
recorded more clips. It answers, with grouped-by-video cross-validation:

  "For each exercise, does adding any candidate feature beat the currently
   shipped feature vector -- by enough to trust?"

WHY grouped-by-video CV: reps from the same video are near-duplicates, so a
random train/test split leaks and inflates accuracy. Holding whole videos out
gives an honest estimate of performance on unseen footage.

GUARDS baked in (learned the hard way):
  * AUC < 0.5 means a feature predicts the label BACKWARDS -- it is noise,
    never trust it no matter how good the CV number looks.
  * Fewer than ~200 rows means grouped CV is unstable (Squat=29, Push-Up=78,
    Pull-Up=96 are all in this bucket). A "gain" on data this small is a guess,
    so the script only recommends a change at >=200 rows.

Typical use:
    python feature_study.py
Read the "baseline" column (current model) and only act on a recommendation
line that says DATA-SUPPORTED.
"""
import csv
import os
from collections import defaultdict

import numpy as np

DATASET = os.path.dirname(os.path.abspath(__file__))
CAND = os.path.join(DATASET, "features_candidates.csv")
FEAT = os.path.join(DATASET, "features.csv")

# candidate columns per exercise
CANDS = {
    "Push-Up": ["pu_torso_angle", "pu_hip_sag", "pu_knee_angle", "pu_head_angle",
                "pu_shoulder_wrist_dx"],
    "Squat": ["sq_shin_angle", "sq_thigh_angle", "sq_hip_angle", "sq_hip_knee_gap",
              "sq_knee_fwd"],
    "Plank": [],  # plank uses plank-style 3-vec; candidates not extracted
    "Side Plank": [],
    "Lunge": [],
    "Pull-Up": ["pl_elbow_angle", "pl_elbow_asym", "pl_wrist_width",
                "pl_shoulder_tilt", "pl_wrist_shoulder_gap"],
}

# shipped feature vector per exercise (the columns the model actually uses)
SHIPPED = {
    "Push-Up": ["feature_1", "feature_2"],
    "Squat": ["feature_1", "feature_2"],
    "Lunge": ["feature_1", "feature_2", "feature_3", "feature_4", "feature_5"],
    "Plank": ["feature_1", "feature_2", "feature_3"],
    "Side Plank": ["feature_1", "feature_2", "feature_3"],
    "Pull-Up": ["feature_1", "feature_2"],
}


def load_cand():
    rows = defaultdict(list)
    with open(CAND, newline="") as f:
        for r in csv.DictReader(f):
            rows[r["exercise"]].append(r)
    return rows


def auc(scores, labels):
    s = np.array(scores, float)
    order = np.argsort(s, kind="mergesort")
    ranks = np.empty(len(s), float)
    ranks[order] = np.arange(1, len(s) + 1)
    for v in np.unique(s):
        m = s == v
        ranks[m] = ranks[m].mean()
    pos = np.array(labels) == 1
    npos, nneg = pos.sum(), (~pos).sum()
    if npos == 0 or nneg == 0:
        return float("nan")
    return (ranks[pos].sum() - npos * (npos + 1) / 2) / (npos * nneg)


def grouped_knn(X, labels, groups, k=5, folds=5, seed=0):
    X = np.asarray(X, float)
    y = np.asarray(labels, int)
    uniq = sorted(set(groups))
    rng = np.random.default_rng(seed)
    rng.shuffle(uniq)
    fold_of = {g: i % folds for i, g in enumerate(uniq)}
    # average over a few seeds for stability on small data
    accs = []
    for sd in range(3):
        rng2 = np.random.default_rng(seed + sd)
        u = list(uniq)
        rng2.shuffle(u)
        fold_of = {g: i % folds for i, g in enumerate(u)}
        corr = tot = 0
        for fo in range(folds):
            te = np.array([fold_of[g] == fo for g in groups])
            tr = ~te
            if te.sum() == 0 or tr.sum() == 0:
                continue
            Xtr, ytr, Xte, yte = X[tr], y[tr], X[te], y[te]
            mean, std = Xtr.mean(0), Xtr.std(0)
            std[std == 0] = 1
            Ztr, Zte = (Xtr - mean) / std, (Xte - mean) / std
            for i in range(len(Zte)):
                d = np.sqrt(((Ztr - Zte[i]) ** 2).sum(1))
                idx = np.argsort(d)[:k]
                pred = 1 if ytr[idx].sum() * 2 > k else 0
                corr += pred == yte[i]
                tot += 1
        if tot:
            accs.append(corr / tot)
    return float(np.mean(accs)) if accs else float("nan")


def main():
    rows = load_cand()
    print(f"{'exercise':11s} {'rows':>6s} {'vids':>5s} | {'baseline':>9s} | "
          f"{'best add':>22s} {'gain':>7s} {'AUC':>6s} {'stable':>7s}")
    print("-" * 82)
    recs = []
    for ex in ["Lunge", "Plank", "Side Plank", "Squat", "Push-Up", "Pull-Up"]:
        rws = rows.get(ex, [])
        if not rws:
            continue
        n = len(rws)
        vids = len(set(r["video_id"] for r in rws))
        groups = [r["video_id"] for r in rws]
        labels = [1 if r["label"] == "correct" else 0 for r in rws]

        def col(c):
            return [float(r[c]) if r.get(c) not in ("", None) else np.nan
                    for r in rws]

        base_cols = SHIPPED[ex]
        # drop rows with any nan in base
        base_mat = np.array([col(c) for c in base_cols]).T
        keep = ~np.isnan(base_mat).any(1)
        Xb = base_mat[keep]
        yb = [labels[i] for i in range(n) if keep[i]]
        gb = [groups[i] for i in range(n) if keep[i]]
        base_acc = grouped_knn(Xb, yb, gb)
        stable = n >= 200
        best = None
        for c in CANDS.get(ex, []):
            v = np.array(col(c), float)
            kk = keep & ~np.isnan(v)
            if kk.sum() < 10:
                continue
            X = np.column_stack([base_mat[kk], v[kk]])
            y = [labels[i] for i in range(n) if kk[i]]
            g = [groups[i] for i in range(n) if kk[i]]
            acc = grouped_knn(X, y, g)
            a = auc(v[kk], y)
            gain = acc - base_acc
            if a == a and a < 0.5:
                gain = -abs(gain)  # penalize inverted features
            if best is None or gain > best[1]:
                best = (c, gain, a, acc)
        tag = "yes" if stable else "NO(small)"
        if best and best[1] > 0.02 and a != a:
            pass
        beststr = f"{best[0]}" if best else "-"
        bestgain = f"{best[1]*100:+.1f}%" if best else "-"
        bestauc = f"{best[2]:.2f}" if best and best[2] == best[2] else "-"
        print(f"{ex:11s} {n:6d} {vids:5d} | {base_acc*100:8.1f}% | "
              f"{beststr:>22s} {bestgain:>7s} {bestauc:>6s} {tag:>7s}")
        if best and best[1] > 0.02 and stable:
            recs.append((ex, best[0], base_acc, best[3], best[2]))
    print()
    if recs:
        print("DATA-SUPPORTED recommendations (>=200 rows, clear gain, AUC>=0.5):")
        for ex, c, b, a, auc_ in recs:
            print(f"  {ex}: add '{c}'  {b*100:.1f}% -> {a*100:.1f}%  (AUC {auc_:.2f})")
    else:
        print("No candidate is supported on a large-enough dataset to ship.")
        print("Small-data exercises (Squat 29, Push-Up 78, Pull-Up 96) cannot")
        print("validate a feature change -- record more multi-rep clips first.")


if __name__ == "__main__":
    main()
