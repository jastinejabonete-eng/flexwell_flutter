"""
train_and_validate.py

Loads features.csv (from the updated extract_features.py), trains a KNN
classifier per exercise, and reports accuracy so you can confirm k=5 (per
the paper) is a reasonable choice before shipping it.

Note: the meaning of feature_1/feature_2 differs by exercise (vertical
displacement + a bilateral ratio for Squat/Push-Up/Pull-Up; an angle + a
side-view-specific measurement for Lunge/Plank/Side Plank) -- see
extract_features.py's docstring for the exact mapping. This script doesn't
need to know the meaning, only that the two columns are consistent within
each exercise's own rows.
"""

import pandas as pd
from sklearn.model_selection import cross_val_score, train_test_split
from sklearn.neighbors import KNeighborsClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import classification_report

df = pd.read_csv("features.csv")
feature_cols = ["feature_1", "feature_2"]

for exercise in df["exercise"].unique():
    subset = df[df["exercise"] == exercise]
    X = subset[feature_cols].values
    y = subset["label"].values

    if len(subset) < 20:
        print(f"\n{exercise}: only {len(subset)} samples -- collect more data before trusting this.")
        continue

    # Scale features so feature_1 and feature_2 contribute comparably to
    # distance, even though they're on very different numeric scales
    # (e.g. a displacement ratio around 0.0-0.5 vs. an angle in degrees).
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)

    print(f"\n=== {exercise} ({len(subset)} samples) ===")
    for k in [3, 5, 7, 9]:
        knn = KNeighborsClassifier(n_neighbors=k)
        scores = cross_val_score(knn, X_scaled, y, cv=5)
        print(f"  k={k}: mean accuracy = {scores.mean():.2f} (+/- {scores.std():.2f})")

    X_train, X_test, y_train, y_test = train_test_split(
        X_scaled, y, test_size=0.2, random_state=42, stratify=y
    )
    knn = KNeighborsClassifier(n_neighbors=5)
    knn.fit(X_train, y_train)
    y_pred = knn.predict(X_test)
    print(f"\n  Holdout test report (k=5):")
    print(classification_report(y_test, y_pred, digits=2))