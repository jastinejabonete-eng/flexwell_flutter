"""Apply the 2026-11-07 trainer-verified fixes and measure the contested pair.

Mandated reverts (trainer watched the videos):
  Side Plank Copy of IMG_0210.mov : correct -> AGAIN incorrect (severe sag)
  Plank       Copy of IMG_0039.mov: incorrect -> AGAIN correct

Contested pair, decided empirically here:
  Pull-Up batch20261012_IMG_3353.mp4 (correct->incorrect at relabel)
  Push-Up  IMG_3296.MOV              (correct->incorrect at relabel)

Writes variant CSVs:
  features_v_revert_only.csv  : 0210 + 0039 reverted, 3353 + 3296 kept flipped
  features_v_revert_plus.csv  : 0210 + 0039 reverted AND 3353 + 3296 reverted
Prints which variant was written and the label audit for the four videos.
"""
import pandas as pd

HERE = r"C:\Users\Janelyn\Downloads\Flutter\Flexwell\flexwell_flutter\DATASET_FLEXWELL\dataset"
ADPT = f"{HERE}\\features.csv"
ORIG = f"{HERE}\\features_before_relabel.csv"

TARGETS = [
    ("Side Plank", "Copy of IMG_0210.mov", "incorrect"),
    ("Plank", "Copy of IMG_0039.mov", "correct"),
    ("Pull-Up", "batch20261012_IMG_3353.mp4", None),  # None = contested
    ("Push-Up", "IMG_3296.MOV", None),
]

orig = pd.read_csv(ORIG)

def revert(df, ex, vid, label):
    m = (df["exercise"] == ex) & (df["video_id"].str.contains(vid))
    n = int(m.sum())
    if n == 0:
        raise SystemExit(f"NOT FOUND: {ex} {vid}")
    df.loc[m, "label"] = label
    return df, n

# variant A: only the mandated reverts
a = pd.read_csv(ADPT)
applied = []
for ex, vid, label in TARGETS:
    if label:
        a, n = revert(a, ex, vid, label)
        applied.append((ex, vid, f"reverted->{label}", n))
a.to_csv(f"{HERE}\\features_v_revert_only.csv", index=False)

# variant B: mandated reverts + both contested back to trainer labels
b = a.copy()
for ex, vid, _ in TARGETS:
    if TARGETS[[t[1] for t in TARGETS].index(vid)][2] is None:
        old = orig[(orig["exercise"] == ex) & (orig["video_id"].str.contains(vid))]["label"].iloc[0]
        b, n = revert(b, ex, vid, old)
        applied.append((ex, vid, f"reverted->{old} (trainer)", n))
b.to_csv(f"{HERE}\\features_v_revert_plus.csv", index=False)

for ex, vid, what, n in applied:
    print(f"{what:28} {ex:11} {vid:32} rows={n}")
print("\nWrote features_v_revert_only.csv and features_v_revert_plus.csv")
