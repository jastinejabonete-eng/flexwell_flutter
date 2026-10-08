# DATASET_FLEXWELL — ML training pipeline for FlexWell

This folder holds the **Python pipeline** that generates the KNN model the
Flutter app uses to judge exercise form. It is the ML side of FlexWell; the
app only ships the final `knn_training_data.json` as a bundled asset.

## Pipeline (run in this order, from inside `dataset/`)

```
labeled videos (dataset/<Exercise>/{correct,incorrect}/*.mov)
        │
        ▼  extract_features.py       → features.csv, rest_values.csv, baseline_scales.csv
        │
        ▼  train_and_validate.py     → accuracy report (checks the model)
        │
        ▼  export_for_app.py         → knn_training_data.json   ← copied to app assets/
```

Helper scripts: `check_batch_leakage.py`, `check_feature_signal.py`,
`diagnose_calibration.py`, `verify_export_parity.py`.

## What is tracked in git vs. not

- **Tracked (small, essential):** all `.py` scripts, `README.md`, the generated
  `knn_training_data.json`, and the CSV outputs. These are the reproducible ML.
- **NOT tracked (large, on disk only):** the raw training videos under
  `dataset/<Exercise>/`, the external `Dataset Exercise Quality-wise/` research
  dataset, and its `.zip`. These are multi-GB; they stay local and are excluded
  via `.gitignore`. They are your source data for adding new training examples
  (e.g. more Squat / Push-Up rows — see the app-side checkup note).

## Adding more training data (e.g. to strengthen Squat / Push-Up)

1. Drop labeled clips into `dataset/<Exercise>/correct/` and `.../incorrect/`.
2. Re-run `extract_features.py`, then `train_and_validate.py` to check accuracy.
3. Run `export_for_app.py` to regenerate `knn_training_data.json`.
4. Copy the new `knn_training_data.json` into the app:
   `flexwell_flutter/assets/knn_training_data.json`.
5. Rebuild the app.

> Note: `features_1`/`feature_2` are `(feature_1, feature_2)` per exercise and
> must stay identical to the Dart-side extractors in
> `flexwell_flutter/lib/pose_analyzer.dart` (see its class comment for the
> per-exercise feature definition). If you change one side, change both.

## Provenance of the reference dataset

`Dataset Exercise Quality-wise/` (+ `.zip`) is the external multi-view fitness
exercise dataset described in the README (26 subjects, 7 exercises, good/bad,
front/side/diagonal views). It is reference/source material, not part of the app.
