"""
downsample_slowmo_lunge.py

A handful of Lunge clips (IMG_2649..IMG_2659) were shot at 240 fps slow-motion.
The extractor samples every 5th frame, so each of those clips emits ~200-256
rows -- far more than a normal 30/60 fps clip (~30-50). Because those rows are
near-duplicate consecutive frames of the same few reps, they let one clip
dominate the KNN and bias it toward "correct".

This script stride-samples each over-represented clip down to CAP rows, keeping
the rows spread across the whole clip (even stride, not a prefix) so temporal
coverage is preserved. Everything else is left untouched.

Usage:  python downsample_slowmo_lunge.py
Reads:  features.csv        (overwritten in place after backing up)
"""
import pandas as pd

CAP = 50  # max rows to keep per slow-motion clip

# The 240 fps Lunge clips. Matched by substring of video_id (robust to path case).
SLOWMO = [f"IMG_26{n:02d}" for n in range(49, 60)]  # IMG_2649 .. IMG_2659


def stride_indices(n, cap):
    """Indices that keep `cap` rows spread evenly across n (inclusive ends)."""
    if n <= cap:
        return list(range(n))
    step = (n - 1) / (cap - 1)
    return sorted({round(i * step) for i in range(cap)})


def main():
    df = pd.read_csv("features.csv")
    print(f"loaded {len(df)} rows")
    print("video_id populated:", df.video_id.notna().sum(), "non-null")
    if df.video_id.notna().sum() == 0:
        raise SystemExit("video_id is empty -- run the corrected extract_features.py first")

    lunge = df.exercise == "Lunge"
    keep_idx = []
    # Group Lunge rows by video_id, preserving original order within each group.
    lung = df[lunge]
    to_drop = set()
    for vid, g in lung.groupby("video_id", sort=False):
        if any(s.lower() in str(vid).lower() for s in SLOWMO):
            idx = list(g.index)
            keep = [idx[i] for i in stride_indices(len(idx), CAP)]
            dropped = len(idx) - len(keep)
            print(f"  {vid}: {len(idx)} -> {len(keep)} rows (dropped {dropped})")
            to_drop.update(set(idx) - set(keep))

    df2 = df.drop(index=list(to_drop))
    print(f"\nkept {len(df2)} / {len(df)} rows (removed {len(df) - len(df2)})")

    df2.to_csv("features.csv", index=False)
    print("wrote features.csv")

    print("\nLunge label balance after downsampling:")
    print(df2[df2.exercise == "Lunge"].groupby("label").size())


if __name__ == "__main__":
    main()
