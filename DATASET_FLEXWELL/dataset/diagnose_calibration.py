"""
diagnose_calibration.py

Your grouped validation shows a sharp split:
  - Side-view exercises (Plank 81-92%, Side Plank 78-83%, Lunge 72-76%)
    generalize reasonably to unseen videos.
  - Calibrated front/back exercises (Squat ~53-56%, Push-Up ~50-55%,
    Pull-Up ~31-37%, i.e. AT OR BELOW the ~50% chance rate for a binary
    task) do not.

That split lines up exactly with a difference in how the features are
built: side-view features (angle, back-line angle, hip-deviation ratio)
are computed independently per frame. Front/back features depend on a
per-VIDEO calibration baseline (average of the first ~10 detected frames).
If that baseline isn't comparable across videos -- e.g. some clips start
mid-rep instead of at rest, or "correct" and "incorrect" videos were shot
at different camera distances / framing -- then vertical_displacement
measures something closer to "which video this frame came from" than
"how deep the rep was", and a classifier trained on that will fail on any
video it hasn't seen, exactly as GroupKFold is now showing you.

This script checks that hypothesis two ways at the VIDEO level (the level
a grouped classifier actually has to generalize across):

  1. Video-level MEAN of feature_1. A per-frame displacement that
     oscillates up and down through each rep tends to average out toward
     zero across a whole clip regardless of form quality -- a deep squat
     and a shallow squat both spend time near the top. So an overlapping
     mean doesn't by itself prove the feature is useless; it may just be
     the wrong statistic.
  2. Video-level EXTREMES (min/max) of feature_1. If "correct" vs
     "incorrect" is about how deep/high a rep actually goes, that signal
     should show up in how far feature_1 swings within a video, not its
     average -- so this is checked separately.

It also flags videos whose |feature_1| is implausibly large (e.g. > 2x
the calibrated torso length), which usually means the calibration
baseline_scale (shoulder-to-hip distance) was near zero for that video --
e.g. because the torso reads as nearly horizontal on-screen (a likely
issue for Push-Up specifically) -- causing division to blow up normal
noise into huge values.
"""
import pandas as pd

FRONT_BACK_EXERCISES = {"Squat", "Push-Up", "Pull-Up"}
SCALE_BLOWUP_THRESHOLD = 2.0

df = pd.read_csv("features.csv")
pd.set_option("display.width", 140)

for exercise in FRONT_BACK_EXERCISES:
    subset = df[df["exercise"] == exercise]
    if subset.empty:
        continue

    per_video = subset.groupby(["video_id", "label"]).agg(
        f1_mean=("feature_1", "mean"),
        f1_min=("feature_1", "min"),
        f1_max=("feature_1", "max"),
        f2_mean=("feature_2", "mean"),
        n_rows=("feature_1", "size"),
    ).reset_index()

    print(f"\n=== {exercise} ===")
    for label in ["correct", "incorrect"]:
        rows = per_video[per_video["label"] == label]
        print(f"  {label:9s}: {len(rows)} videos")
        print(f"    per-video MEAN   range [{rows['f1_mean'].min():.3f}, {rows['f1_mean'].max():.3f}]")
        print(f"    per-video MIN    range [{rows['f1_min'].min():.3f}, {rows['f1_min'].max():.3f}]")
        print(f"    per-video MAX    range [{rows['f1_max'].min():.3f}, {rows['f1_max'].max():.3f}]")

    correct = per_video[per_video["label"] == "correct"]
    incorrect = per_video[per_video["label"] == "incorrect"]

    def overlaps(a, b):
        return not (a.max() < b.min() or b.max() < a.min())

    print(f"  -> MEAN ranges {'OVERLAP' if overlaps(correct['f1_mean'], incorrect['f1_mean']) else 'separated'}"
          f" | MIN ranges {'OVERLAP' if overlaps(correct['f1_min'], incorrect['f1_min']) else 'separated'}"
          f" | MAX ranges {'OVERLAP' if overlaps(correct['f1_max'], incorrect['f1_max']) else 'separated'}")

    print(f"  rows per video: min={per_video['n_rows'].min()}, "
          f"max={per_video['n_rows'].max()}, mean={per_video['n_rows'].mean():.0f}")

    blown_up = per_video[
        (per_video["f1_min"].abs() > SCALE_BLOWUP_THRESHOLD) | (per_video["f1_max"].abs() > SCALE_BLOWUP_THRESHOLD)
    ]
    if len(blown_up) > 0:
        print(f"  {len(blown_up)} video(s) with |feature_1| > {SCALE_BLOWUP_THRESHOLD} "
              f"(likely near-zero baseline_scale for that clip):")
        for _, r in blown_up.iterrows():
            print(f"    {r['video_id']} [{r['label']}]: min={r['f1_min']:.3f}, max={r['f1_max']:.3f}")

print(
    "\nHow to read this:\n"
    "  - MEAN overlapping but MIN/MAX separated: the feature does carry "
    "form signal, but the per-frame training rows need to be built from "
    "rep extremes (e.g. one row per rep at its deepest point) rather than "
    "every raw frame -- the current per-frame averaging/row scheme is "
    "burying the signal.\n"
    "  - MIN/MAX also overlapping: the feature isn't separating form at "
    "this exercise at all -- calibration or feature choice needs a "
    "rework, not just resampling.\n"
    "  - Any videos listed under the blow-up check: open those clips. If "
    "many belong to one exercise (Push-Up is the prime suspect), the "
    "shoulder-hip 'torso_length' scale is likely near zero for that "
    "camera angle and needs a different normalization.\n"
)