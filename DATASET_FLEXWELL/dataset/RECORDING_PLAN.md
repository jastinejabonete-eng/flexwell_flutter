# FlexWell Squat — Recording Plan

Goal: replace the current 28-row Squat model (one person, one rep per clip) with a
diverse dataset that generalizes across bodies and camera setups.

## What the model actually learned (from the current 28 rows)
The real discriminator is **torso lean at the bottom of the squat**, not knee depth:

- **Correct** (14 rows): knee angle 32–40°, **lean 33–40°** — controlled forward lean.
- **Incorrect** (14 rows): lean either **too upright (<20°, some leaning back)** or
  **collapsing forward (>60°)**.

So we must teach the boundary (lean ~30–45° = correct) across different people,
distances, and angles — not just re-record one person.

## What to record

Record from **2–5 different people** (2 is fine if chosen for noticeably different
builds — e.g. different heights, or one leaner/one heavier; more people = better
generalization). Each person does:

| Label      | Clips per person | Reps per clip | Form |
|------------|------------------|---------------|------|
| `correct`  | 4–5              | 5–8           | Controlled depth, lean ~30–45° at bottom |
| `incorrect`| 6–8              | 5–8           | Both failure modes below |

**Both incorrect failure modes go in the same `incorrect/` folder:**
- **Too upright:** stay vertical, knees barely pass 90°, lean <20° (some lean back).
- **Collapsing forward:** knees cave, chest drops, lean >60° at the bottom.

**Vary across clips** (not every clip):
- Camera distance: 2m / 3m / 4m
- Camera height: floor / table / shelf

**Fixed requirements (do not vary):**
- Film the **left side profile** — the model was trained on left-side view only.
- Whole body in frame, head to toe, stable/mounted camera.
- Well-lit, no backlighting, fitted clothing.

## Video specs
- 1080p @ 30 or 60 fps. **NOT 240fps slow-motion** (slow-mo caused the earlier
  row-dominance problem; a 240fps clip emits ~250 rows and skews training).
- 5–10 seconds per clip, 5–8 reps per clip.
- Portrait orientation.

## Target
- 2 people × ~12 clips = **~24 clips × ~6 reps ≈ 150+ rows** (2 is the minimum;
  more people or clips = better).

## Folder layout (extract_features.py reads exactly this)
```
DATASET_FLEXWELL/dataset/Squat/
  correct/     <- controlled-depth, lean ~30-45 deg
  incorrect/   <- too-upright AND collapsing-forward, mixed
```
Drop the .mov/.mp4 clips directly into `correct/` and `incorrect/`. Names don't matter.

## After recording — run the pipeline (I will run this):
```
extract_features.py        # regenerate features.csv
train_and_validate.py      # confirm honest grouped-by-video accuracy
export_for_app.py          # regenerate knn_training_data.json
copy to assets/knn_training_data.json
```
Then verify on-device (debug logcat: `[KNN scaler] ... ok`).

## Note on the current model
Until this lands, the shipped Squat model works for the person/angle it was
recorded from — acceptable for the capstone, but this plan makes it generalize.
