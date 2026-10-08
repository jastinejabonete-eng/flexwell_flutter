"""
export_for_app.py

Converts features.csv into a JSON file the mobile app can bundle as an
asset and use directly for KNN inference on-device.

Since feature_1 and feature_2 are on very different numeric scales for some
exercises (e.g. a displacement ratio around 0.0-0.5 vs. an angle in
degrees), this script also computes and saves the per-exercise mean/std of
each feature, so the Dart-side classifier can apply the SAME z-score
normalization at inference time that train_and_validate.py used for
validation. Without this, one feature could silently dominate the distance
calculation on-device.
"""

import pandas as pd
import json

df = pd.read_csv("features.csv")
feature_cols = ["feature_1", "feature_2"]

output = {}
for exercise in df["exercise"].unique():
    subset = df[df["exercise"] == exercise]

    means = subset[feature_cols].mean()
    stds = subset[feature_cols].std(ddof=0)
    stds = stds.replace(0, 1.0)  # avoid divide-by-zero if a feature is constant

    output[exercise] = {
        "mean": means.tolist(),
        "std": stds.tolist(),
        "examples": [
            {
                "features": row[feature_cols].tolist(),
                "label": row["label"],
            }
            for _, row in subset.iterrows()
        ],
    }

with open("knn_training_data.json", "w") as f:
    json.dump(output, f, indent=2)

print("Wrote knn_training_data.json")
for exercise, data in output.items():
    print(f"  {exercise}: {len(data['examples'])} examples, mean={data['mean']}, std={data['std']}")