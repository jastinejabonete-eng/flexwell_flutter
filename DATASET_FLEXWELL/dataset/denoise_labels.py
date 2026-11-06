"""
denoise_labels.py -- label-cleanup TRIAL for features.csv (2026-11-06).

Does NOT modify features.csv. Produces two candidate datasets and a report:

  features_relabeled.csv : rows of every video whose conflict score passes the
                           rule are FLIPPED (label -> the vote's majority).
  features_dropped.csv   : rows of those videos REMOVED.

Conflict rule (leave-one-video-out kNN on video frames):
  frame_disagree >= 0.80  AND  centroid vote disagrees with the video label.
  (Video centroid and frame majority agreed in direction for every video in
  the audit, so one threshold set is used.)

Also writes denoise_report.csv listing every action.

Usage:
  python denoise_labels.py [exercises ...]   (default: all)
"""
import os
import sys

import numpy as np
import pandas as pd

import audit_label_mixing as audit

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "features.csv")
FRAME_DISAGREE_MIN = float(os.environ.get("DENOISE_THRESHOLD", "0.80"))


def flagged_videos(df, exercise):
    sub = df[df["exercise"] == exercise]
    cols = [f"feature_{i}" for i in range(1, 6)
            if sub[f"feature_{i}"].notna().all()]
    out = []
    for vid, g in sub.groupby("video_id"):
        pool_X = sub.loc[~(sub["video_id"] == vid), cols]
        pool_y = sub.loc[~(sub["video_id"] == vid), "label"].to_numpy()
        votes = audit.frame_votes(pool_X, pool_y, g[cols])
        frac = float(np.mean((votes > audit.K // 2)
                             != (g["label"].to_numpy() != "correct")))
        centroid = np.asarray(g[cols].mean(axis=0)).reshape(1, -1)
        cv = int(audit.frame_votes(pool_X, pool_y, centroid)[0]) > audit.K // 2
        video_incorrect = g["label"].iloc[0] != "correct"
        if frac >= FRAME_DISAGREE_MIN and (cv != video_incorrect):
            out.append((vid, frac, "incorrect" if cv else "correct"))
    return out


def main():
    df = pd.read_csv(SRC)
    targets = sys.argv[1:] or sorted(df["exercise"].unique())

    actions = []
    lab = df.copy()
    drop = df.copy()
    for ex in targets:
        for vid, frac, new_label in flagged_videos(df, ex):
            mask = (lab["exercise"] == ex) & (lab["video_id"] == vid)
            old = lab.loc[mask, "label"].iloc[0]
            if old != new_label:
                actions.append((ex, vid, old, new_label, "flip", frac))
                lab.loc[mask, "label"] = new_label
                drop = drop[~((drop["exercise"] == ex)
                              & (drop["video_id"] == vid))]
            else:
                actions.append((ex, vid, old, new_label, "keep?", frac))
    rep = pd.DataFrame(actions, columns=["exercise", "video", "old_label",
                                         "proposed_label", "action",
                                         "frame_disagree"])
    rep.to_csv(os.path.join(HERE, "denoise_report.csv"), index=False)
    lab.to_csv(os.path.join(HERE, "features_relabeled.csv"), index=False)
    drop.to_csv(os.path.join(HERE, "features_dropped.csv"), index=False)

    print(f"flagged & actioned: {len(rep)} videos")
    print(rep.groupby(["exercise", "action"]).size())
    for name, d in ("relabeled", lab), ("dropped", drop):
        sizes = d.groupby(["exercise", "label"]).size().unstack()
        print(f"\n{name}: rows per exercise/label")
        print(sizes)


if __name__ == "__main__":
    main()
