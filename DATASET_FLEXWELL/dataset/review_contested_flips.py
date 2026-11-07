"""Review the four contested video flips with full feature evidence.

Prints per-row features, per-class feature stats, the LOVO frame votes and
the per-class neighborhood composition around each video's rows.
"""
import numpy as np
import pandas as pd

REL = "DATASET_FLEXWELL/dataset/features.csv"  # adopted (relabeled) csv
ORIG = "DATASET_FLEXWELL/dataset/features_before_relabel.csv"

cur = pd.read_csv(REL)
orig = pd.read_csv(ORIG)

CASES = [
    ("Pull-Up", "batch20261012_IMG_3353.mp4"),
    ("Push-Up", "IMG_3296.MOV"),
]


def stats(df, ex):
    sub = df[df["exercise"] == ex]
    cols = [f"feature_{i}" for i in range(1, 6)
            if sub[f"feature_{i}"].notna().all()]
    g = sub[sub["label"] == "correct"][cols]
    b = sub[sub["label"] != "correct"][cols]
    return cols, (g.mean(), g.std()), (b.mean(), b.std()), (len(g), len(b))


for ex, vid in CASES:
    rows = cur[cur["exercise"] == ex]
    v = rows[rows["video_id"].str.contains(vid)]
    cols = [f"feature_{i}" for i in range(1, 6)
            if rows[f"feature_{i}"].notna().all()]
    (gm, gs), (bm, bs), n = stats(cur, ex)[1], stats(cur, ex)[2], stats(cur, ex)[3]
    print(f"=== {ex} {vid} (current label {v['label'].iloc[0]}, "
          f"original {orig[(orig.exercise == ex) & (orig.video_id.str.contains(vid))]['label'].iloc[0]}) ===")
    print(f"  class stats: correct n={n[0]} mean={np.round(gm,2).tolist()} std={np.round(gs,2).tolist()}")
    print(f"               incorrect n={n[1]} mean={np.round(bm,2).tolist()} std={np.round(bs,2).tolist()}")
    X = rows[cols].to_numpy(); y = rows["label"].to_numpy()
    mu, sd = X.mean(0), X.std(0)
    sd[sd == 0] = 1e-9
    for _, r in v.iterrows():
        zv = np.asarray(r[cols], dtype=float)
        z = (zv - mu) / sd
        d = np.sqrt(((np.asarray(X) - mu) / sd - z) ** 2).sum(1)
        idx = np.argsort(d)[:5]
        nb = [(round(d[i], 2), y[i]) for i in idx]
        zd = (zv - gm) / gs
        zbad = (zv - bm) / bs
        print(f"  row: feats={[round(x, 2) for x in (zv.tolist())]} "
              f"| z to correct-mean={np.abs(zd).round(2).tolist()} "
              f"| z to incorrect-mean={np.abs(zbad).round(2).tolist()} "
              f"| 5-NN={nb}")
    print()
