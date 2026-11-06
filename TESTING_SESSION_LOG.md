# FlexWell Testing Session Log

**Date:** 2026-11-06
**Repo:** `C:\Users\Janelyn\Downloads\Flutter\Flexwell\flexwell_flutter` (origin: jastinejabonete-eng/flexwell_flutter)

## Session goal
Verify and test FlexWell (Flutter posture-detection app: ML Kit pose + on-device KNN, 6 exercises).

## What was done (chronological)

### 1. Located the project
- Original repo: `C:\Users\Janelyn\Downloads\Flutter\Flexwell\flexwell_flutter` (has git, remote = GitHub flexwell_flutter)
- Clone: `flexwell_TEST_NEW_DATASET` — was exactly in sync with origin/master
- Old dataset dir: `C:\Users\Janelyn\DATASET_FLEXWELL` (used by earlier Codex sessions)

### 2. Initial verification of the "original" folder
- Was 17 commits behind origin/master (origin head = `3172f9e`)
- `test/` had only 3 files vs 13 in `TEST_RESULTS.md` (audit 2026-11-04): knn_core_test.dart, widget_test.dart, simulation_test.dart.bak
- Flutter SDK 3.44.9 / Dart 3.12.2 confirmed working
- Results before sync: `flutter analyze` 0 issues; `flutter test` 20/20 pass (own 3-file suite)

### 3. Fast-forwarded to origin (`761eb1c` → `3172f9e`, 17 commits)
- Copied test files from TEST_NEW_DATASET first (fail: tests written for newer lib APIs);
  reverted copies, then `git pull --ff-only` brought the real 10-file suite + new lib files:
  - lib/onboarding_service.dart, onboarding_tour_overlay.dart, onboarding_tour_steps.dart
  - lib/theme_preference.dart, firebase_status.dart, exercise_camera_guide.dart, exercise_camera_setup_dialog.dart, pose_landmark_requirements.dart
  - Rewritten assets/knn_training_data.json (Pull-Up upgraded to 2-D incl. elbow angle)
- Old 3-file test suite preserved at `test_original_backup\`

### 4. Fixed two committed-code bugs (both pushed)
- **lib/knn_classifier.dart**: added public read-only `models` getter
  (`Map.unmodifiable(Map<String, FlatKnnModel>.from(_models))`) — integration_pipeline_test.dart referenced it; it could never compile before.
- **test/integration_pipeline_test.dart**: Luge... (typo) Lunge dims assertion 2→5. Verified 5-D is
  correct in three places: pose_analyzer.dart `_lungeFeatures` (kneeAngle, torsoLean, shinAngle,
  hipAnkleGap, thighAngle), export_for_app.py ("Lunge emits 5"), feature_study.py (features 1-5).

### 5. Pushed commit
- `a5d78e7` "Fix integration pipeline test: add KnnClassifier.models getter, correct Lunge dims to 5"

### 6. Final automated suite state (after fixes)
- `flutter analyze`: 0 issues
- `flutter test`: **64/64 tests pass** (10 files: dashboard 3, exercise_camera_setup_dialog 10,
  integration_pipeline 10, knn_core 19, onboarding_tour 6, pose_analyzer 5, pose_painter 10,
  summary 5, tutorials 1, widget 3)
- NOTE: audit's "79 tests" was stale (rep_counter_test.dart 14 tests does not exist on origin)
- KNN scaler sanity inside tests: all 17 features across 6 exercises normalize correctly

### 7. Simulation test re-enabled and REWRITTEN (2026-11-06)
- Renamed `test/simulation_test.dart.bak` → `test/simulation_test.dart`, then
  rewrote the synthetic pose generators. The OLD harness had three harness bugs:
  1. `'Side Plank (good)'.split(' ')[0]` → `'Side'` (not a model key) caused the
     "Form model unavailable" messages — fixed with an `exerciseKeyFor()` map.
  2. Plank-style bodies were vertical (shoulder/hip/ankle stacked) so
     `_bodyLineIsHorizontal()` never passed → Push-Up/Plank/Side Plank never
     calibrated or engaged.
  3. Joint angles were never built into joint positions (knee placed straight
     between hip and ankle measured ~174° on a "good squat"; arms had no IK so
     Pull-Up elbows measured ~176° at the "top").
- New geometry: forward-offset knees (interior angle = 180 − 2e), horizontal
  plank-style bodies, two-bone IK arms anchored on fixed wrists/bar, pike-plank
  hips matching training means, tuned proportions so measured features land on
  the training cluster means. Uses `PoseAnalyzer(clock:)` + real
  `KnnClassifier.instance` from assets.
- Added `test/predict_probe.py` — probes feature vectors against
  assets/knn_training_data.json (k=5 vote in z-space, nearest-z + OOD report).

## FINAL simulation results (2026-11-06 run, real KNN model)
| Trace | Verdict | Correct? |
|---|---|---|
| Squat good | 🟢 true (peak [59.8, 35.1]) | ✅ |
| Squat bad | 🔴 false (peak [141.1, 11.6], "Check your depth") | ✅ |
| Push-Up good | 🟢 true (peak [65.5, 173.1]) | ✅ (audit's Push-Up false-negative FIXED in sim) |
| Push-Up shallow/bad | never engages (disp ≤ 0.09 < 0.12 threshold) | by design: shallow reps don't register |
| Pull-Up good | 🟢 true (peak [-0.92, 14.3]) — no more OOD | ✅ |
| Pull-Up partial | 🔴 false ("Pull higher and keep your elbows in") | ✅ |
| Plank good | 🔴 false | ❌ model/data issue (see root cause) |
| Plank sagging | 🔴 false | ✅ |
| Side Plank good | 🔴 false | ❌ model/data issue |
| Side Plank sagging | 🔴 false | ✅ |
| Lunge good frames | mostly false | ❌ model/data issue |
| Lunge bad frames | mostly false (one spurious true) | ⚠️ noisy |

## ROOT CAUSE (proven with test/predict_probe.py)
Probes AT THE EXACT good-cluster means of the failing exercises still vote
incorrect among their own k=5 nearest neighbours:
- Plank [168.2, 0.0486, 0.043] → 4/5 bad, nearest z 0.03 labeled *incorrect*
- Side Plank [168.2, 0.0486, 0.12] → 4/5 bad, nearest z 0.07
- Lunge [138.3, 5.2, 20.8, 1.3, 20.8] → 5/5 bad, nearest z 0.19
⇒ TRAINING DATA label mixing for Plank / Side Plank / Lunge: good rows sit
inside incorrect-labelled neighbourhoods. DATASET problem, not app code.
(E.g. a training row [177.2, 0.01, 0.06] — a PERFECT straight-line plank — is
labeled 'incorrect', while the 'correct' cluster mean has MORE hip deviation.)
Working exercises (Squat, Push-Up, Pull-Up) classify correctly at cluster means.
Also: Pull-Up oodRadius is only 0.59 z-units (Squat 1.75, Lunge 8.0) — very tight.

## Phase 2: ML pipeline audit (2026-11-06, continued)

### What the pipeline looks like
- Labels are VIDEO-level, from folder names: `features.csv` rows inherit
  `<Exercise>/<label>/<file>.mov` even when a frame's pose matches the other
  class (DATASET_FLEXWELL/dataset/extract_features.py main()).
- train_and_validate.py (video-grouped CV): Lunge .85, Plank .80, Push-Up .86,
  Side Plank .78, Squat .93, Pull-Up .78 (but Pull-Up holdout recall for
  correct is only 0.50 with 32 held-out rows).
- export_for_app.py: row-level held-out oodRadius ALWAYS collapses (0.18–0.70)
  because same-video near-duplicate rows contaminate the holdout; the live-video
  replay fallback (mediapipe, ≤4 vids, ≤200 frames) rescues every exercise.
  Shipped radii (dataset json == assets json, byte-identical) ARE live-calibrated;
  Pull-Up 0.5871 equals live p99 (max observed 0.630, only 274 frames replayed
  so the tail is undersampled). Re-running the export is nearly deterministic
  except Squat radius (1.7524 -> 2.1235 run-to-run) — keep committed values.

### Label-mixing audit (audit_label_mixing.py, leave-one-video-out kNN)
Saved full report: DATASET_FLEXWELL/dataset/audit_label_mixing_output.txt
Per-video frame votes against the video's own label:
- Side Plank: 17/115 videos >50% disagree (21.0% mean), incl. a batch of
  IMG_02xx videos labeled incorrect whose frames vote CORRECT 87–100%, and
  correct-labeled 0181/0182/0183/0074(1) voting incorrect 64–83%
  (checked values: incorrect-labeled IMG_0207 has a PERFECT body line
  f1=178, f2=0.008; IMG_0210's features are even deeper in the bad range
  f1=145 than the incorrect cluster mean 164 — bad region too sparse)
- Lunge: 6/80 (22.0%); Plank: 3/72 (16.4%), incl. correct-labeled IMG_0039
  (85% disagree, features f1=164/f2=0.068 mid-cluster)
- Pull-Up: 5/67 (18.9%); Push-Up: 11/71 (16.2%) — but only 1-row videos
  mostly; Squat: 2/39 (5.1%) — cleanest
- k-increase does NOT fix the failing probes (probe_k.py: Side Plank good-mean
  stays 20/21 bad at k=21; Lunge 24/31 bad at k=31).
Conclusion: overlapping/undersampled neighborhoods + some genuinely dubious
video labels (candidates for relabel/drop); not fixable by k or app code.

### Decision pending: how to handle the 33 conflicted videos
Options: (a) relabel/drop only high-confidence conflicts (>=80% frames
disagree + centroid disagrees) -> retrain/validate/re-export; (b) produce a
trainer-review report only; (c) record better data. Do not change anything
until user chooses.

### Relabel TRIAL results (user chose the trial run)
Tooling added in DATASET_FLEXWELL/dataset (all untracked):
- audit_label_mixing.py (leave-one-video-out frame-vote audit)
- denoise_labels.py (candidates: features_relabeled.csv / features_dropped.csv
  + denoise_report.csv; threshold via DENOISE_THRESHOLD env, default 0.80)
- probe_k.py (k-sweep), probe_trial.py (trial-vs-shipped model probes),
  compare_models.py (dataset<->assets diff)
- train_and_validate.py / export_for_app.py now accept optional
  input/output path argv (defaults unchanged).

Conservative relabel (24 videos flipped, >=80% frames + centroid disagree):
| Exercise   | k=5 grouped CV before -> after |
|------------|-------------------------------|
| Lunge      | 0.85 -> 0.86 |
| Plank      | 0.80 -> 0.81 |
| Push-Up    | 0.86 -> 0.95 |
| Side Plank | 0.78 -> 0.80 |
| Squat      | 0.93 -> 0.98 |
| Pull-Up    | 0.78 -> 0.82 |

Probes (trial vs shipped model):
- FIXED: Push-Up good mean [60,173] 2/5 bad -> 0/5 bad (correct), with the
  bad bottom probe unchanged (5/5 bad). No probe regressed.
- NOT FIXED (still inverted): Plank good [168.2,.0486,.043] 4/5 bad,
  Side Plank good [168.2,.0486,.12] 4/5 bad,
  Lunge good mean 5/5 bad. Those neighbourhoods are poisoned by
  moderately-conflicted videos (40-60% frame disagreement) that the
  conservative rule deliberately leaves alone.
- Aggressive variant (0.5 threshold, 22 further flips) made probes WORSE
  (Side Plank good 4/5 -> 5/5, Push-Up good 2/5) -> rejected; conservative
  variant is the recommended candidate.

Conclusion: relabeling whole videos is only a partial remedy. The remaining
inversions would need frame-level label refinement or new/better features --
not safely automatable without trainer review of the actual videos.

### Adoption (user approved) -- RELABEL MODEL SHIPPED
- features.csv replaced with the relabeled candidate (original preserved at
  DATASET_FLEXWELL/dataset/features_before_relabel.csv).
- Re-ran extract->export (export_for_app.py, live-video calibration ran) and
  copied the new knn_training_data.json to assets/ (compare_models.py: identical).
- Verification after adoption: python probe (Push-Up good mean now 0/5 bad;
  no other probe regressed) + flutter analyze 0 issues + flutter test 65/65 +
  simulation test (Squat good/bad, Push-Up good, Pull-Up good/partial all
  correct as before).
- Known remaining limitation (unchanged by this): Plank/Side Plank/Lunge
  good-form at cluster means still vote incorrect (frame-level label mixing);
  real fix needs frame-level labels or better features + trainer review.
- Squat oodRadius updated by the re-export (1.7524 -> 2.1235, live-calibrated).

## Remaining work (the "other" — deferred)
1. ML pipeline re-validation: Plank/Side Plank/Lunge label audit, Pull-Up
   oodRadius widening; re-extract → re-export → re-validate
   (DATASET_FLEXWELL/dataset: extract_features.py → export_for_app.py →
   train_and_validate.py)
2. Device/manual testing + 20-min stress test (device_check_protocol.md)
3. Push-Up shallow-rep UX: reps under disp 0.12 never register (by design?)
4. TEST_RESULTS.md in repo still stale (claims 79 tests); real suite = 64 tests

## Files changed in repo
- lib/knn_classifier.dart (+getter) — COMMITTED
- test/integration_pipeline_test.dart (Lunge dims 2→5) — COMMITTED
  (both pushed as a5d78e7 on master)
- test/simulation_test.dart (rewritten harness) — COMMITTED & PUSHED (081daf9)
- test/predict_probe.py (KNN probe tool) — COMMITTED & PUSHED (081daf9)
- TESTING_SESSION_LOG.md (this file) — COMMITTED & PUSHED (081daf9)
- test_original_backup\ (old 3-file suite before fast-forward) — untracked helper
- sim_out.txt (last sim run output) — untracked, disposable
